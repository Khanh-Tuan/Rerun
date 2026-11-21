import Foundation
import StoreKit
import WebKit

/// Bridges premium skin purchases between the game (JavaScript) and the App Store (StoreKit 2).
///
/// The game posts messages to `window.webkit.messageHandlers.iap`:
///   { type: "products", ids: [...] }   ask for local prices (and what this Apple ID already owns)
///   { type: "buy", id: "afterlap.skin.<id>" }
///   { type: "restore" }
/// and receives answers through `window.afterlapIAP({...})`:
///   { type: "products", items: [{ id, price }] }
///   { type: "owned", ids: [...], restore: Bool }
///   { type: "result", id, ok, error? }   error: cancelled | pending | unverified | unavailable | failed
///
/// Premium skins are non-consumable products. Their product IDs are "afterlap.skin." + the skin id
/// (for example "afterlap.skin.emberwyrm"); create them in App Store Connect with the same IDs.
final class Purchases: NSObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    private var updates: Task<Void, Never>?

    override init() {
        super.init()
        // Purchases approved later (Ask to Buy) or made on another device arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.sendOwned(restore: false)
            }
        }
    }

    deinit { updates?.cancel() }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        Task {
            switch type {
            case "products": await products(body["ids"] as? [String] ?? [])
            case "buy": await buy(body["id"] as? String ?? "")
            case "restore": await restore()
            default: break
            }
        }
    }

    private func products(_ ids: [String]) async {
        let clean = ids.filter { $0.hasPrefix("afterlap.skin.") }
        if let found = try? await Product.products(for: clean) {
            send(["type": "products", "items": found.map { ["id": $0.id, "price": $0.displayPrice] }])
        }
        await sendOwned(restore: false)
    }

    private func buy(_ id: String) async {
        guard id.hasPrefix("afterlap.skin.") else { return }
        do {
            guard let product = try await Product.products(for: [id]).first else {
                send(["type": "result", "id": id, "ok": false, "error": "unavailable"]); return
            }
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    send(["type": "result", "id": id, "ok": true])
                } else {
                    send(["type": "result", "id": id, "ok": false, "error": "unverified"])
                }
            case .pending:
                send(["type": "result", "id": id, "ok": false, "error": "pending"])
            case .userCancelled:
                send(["type": "result", "id": id, "ok": false, "error": "cancelled"])
            @unknown default:
                send(["type": "result", "id": id, "ok": false, "error": "failed"])
            }
        } catch {
            send(["type": "result", "id": id, "ok": false, "error": "failed"])
        }
    }

    private func restore() async {
        try? await AppStore.sync()
        await sendOwned(restore: true)
    }

    /// Everything this Apple ID owns (verified, not refunded).
    private func sendOwned(restore: Bool) async {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, t.productID.hasPrefix("afterlap.skin.") {
                ids.append(t.productID)
            }
        }
        send(["type": "owned", "ids": ids, "restore": restore])
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.web?.evaluateJavaScript("window.afterlapIAP && window.afterlapIAP(\(json))")
        }
    }
}
