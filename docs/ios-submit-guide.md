# Building and submitting the iOS app

Who does what:

- **Account owner (Windows):** owns the Apple Developer account. Does the App Store Connect steps in a web browser (any computer works).
- **Builder (Mac):** builds the app in Xcode and uploads it.

Apple's screens and requirements change from time to time. If something below doesn't match what you see, follow Apple's current on-screen instructions and the [App Store Connect Help](https://developer.apple.com/help/app-store-connect/).

---

## Part A: Account owner (any browser)

### 1. Give the builder access to your developer team

1. Go to **appstoreconnect.apple.com** → **Users and Access** → **+**.
2. Invite the builder with their own Apple ID email.
3. Give them a role that can create signing certificates and upload builds. **Admin** is the simplest. A more limited role may work if you also enable access to Certificates, Identifiers & Profiles; check Apple's role descriptions.

Don't share your own Apple ID password. Two-factor codes would come to your devices anyway.

### 2. Create the app record

1. App Store Connect → **Apps** → **+** → **New App**.
2. Platform **iOS**. Name: your final game name (it must be unique on the App Store).
3. **Bundle ID:** pick or register one, for example `com.yourname.rerun`. Tell the builder exactly what it is.
4. SKU: any internal code, for example `rerun-001`.

### 3. Fill in the listing

- **Category:** Games → Arcade (add Casual as secondary if you like).
- **Description, keywords, support URL.**
- **Screenshots:** App Store Connect shows the required iPhone sizes. The builder can take them in the iOS Simulator (File → Save Screen).
- **Privacy policy URL:** publish `docs/privacy-policy.md` somewhere public (a simple web page) and paste the link.
- **App Privacy:** the game collects no data and makes no network requests (fonts are bundled), so you can answer **Data Not Collected**.
- **Age rating questionnaire:** no violence, no gambling, no user content. It should come out at the lowest rating.
- **Price:** free or paid. The game has no in-app purchases (stars are earned only by playing).

---

## Part B: Builder (Mac)

### 1. One-time setup

1. Install **Xcode** from the Mac App Store and open it once so it finishes installing.
2. Install Homebrew from **brew.sh**, then XcodeGen:
   ```
   brew install xcodegen
   ```
3. In Xcode → **Settings** → **Accounts**, add your Apple ID. You should see the account owner's team listed after accepting the invitation from Part A.

### 2. Get the code

Download the repository from GitHub (**Code** → **Download ZIP**) and unzip it, or clone it.

### 3. Generate and open the Xcode project

```
cd path/to/rerun/ios
xcodegen
open Rerun.xcodeproj
```

### 4. Signing and bundle ID

1. Click the **Rerun** project → **Rerun** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing** and choose the account owner's **Team**.
3. Set **Bundle Identifier** to exactly the one from Part A step 2.

To make this permanent, also change `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml`, because running `xcodegen` again overwrites the project.

### 5. Test

1. Pick an iPhone simulator at the top and press **Run** (▶).
2. Check: the game fills the screen, the pixel and neon fonts show (not plain system text), tapping switches lanes, sound plays after the first tap, and the best score is still there after quitting and reopening. Try it once in Airplane Mode too.
3. If possible, also run it on a real iPhone connected by cable.

### 6. Upload

1. Set the run destination to **Any iOS Device (arm64)**.
2. **Product** → **Archive**.
3. In the Organizer window that opens, choose the archive → **Distribute App** → **App Store Connect** → **Upload**, and follow the prompts.
4. The build appears in App Store Connect after processing, usually within an hour.

For each new upload, raise the build number (`CURRENT_PROJECT_VERSION` in `ios/project.yml`, or in Xcode under General → Build).

---

## Part C: Account owner submits for review

1. App Store Connect → your app → the version page → **Build** → choose the uploaded build.
2. Optional: test it first with **TestFlight** on your own iPhone.
3. Click **Add for Review** / **Submit**.

## Things App Review may look at

- **Minimum functionality (guideline 4.2):** apps that are just a website in a wrapper can be rejected. Rerun is bundled inside the app (fonts included), works fully offline and plays full-screen like a native game, which helps.
- **Name:** the App Store name must be unique, and "Rerun" may already be taken.
- **Encryption export question:** the project already declares that the app uses no non-exempt encryption.
