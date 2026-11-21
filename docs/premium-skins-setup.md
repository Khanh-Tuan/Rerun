# Premium skins: App Store setup

Premium skins are optional, cosmetic-only purchases in the iPhone app. Until the products below exist in App Store Connect, nothing can be bought: a purchase attempt reports that the item isn't available.

## 1. Agreements

In App Store Connect: **Business** → accept the **Paid Apps Agreement** and fill in bank and tax details. In-app purchases don't work without it.

## 2. Create the products

App → **Monetization → In-App Purchases** → **+**. For each skin:

- **Type:** Non-Consumable
- **Reference name:** the skin's name (for example "Ember Wyrm")
- **Product ID:** `afterlap.skin.` + the skin id, exactly as below
- **Price:** the tier matching the price shown in the game
- **Display name / description:** the skin's name and its one-line description
- **Review screenshot:** a screenshot of the skin in the Skins screen

| Product ID | Skin | Set | Price |
|---|---|---|---|
| `afterlap.skin.emberwyrm` | Ember Wyrm | Mythic Beasts | $2.99 |
| `afterlap.skin.stormleviathan` | Storm Leviathan | Mythic Beasts | $1.99 |
| `afterlap.skin.kitsune` | Kitsune | Mythic Beasts | $1.99 |
| `afterlap.skin.valkyrie` | Valkyrie | Legendary Heroes | $1.99 |
| `afterlap.skin.shadowronin` | Shadow Ronin | Legendary Heroes | $1.99 |
| `afterlap.skin.spellblade` | Spellblade | Legendary Heroes | $2.99 |
| `afterlap.skin.nebulaqueen` | Nebula Queen | Celestial | $2.99 |
| `afterlap.skin.blacksun` | Black Sun | Celestial | $1.99 |
| `afterlap.skin.zodiac` | Zodiac | Celestial | $0.99 |
| `afterlap.skin.lichking` | Lich King | Dark Fantasy | $2.99 |
| `afterlap.skin.vampirelord` | Vampire Lord | Dark Fantasy | $1.99 |
| `afterlap.skin.reaper` | Reaper | Dark Fantasy | $1.99 |
| `afterlap.skin.magmatitan` | Magma Titan | Elemental Lords | $1.99 |
| `afterlap.skin.tidecaller` | Tidecaller | Elemental Lords | $1.99 |
| `afterlap.skin.tempest` | Tempest | Elemental Lords | $2.99 |
| `afterlap.skin.netrunner` | Netrunner | Cyberpunk | $1.99 |
| `afterlap.skin.mechacore` | Mecha Core | Cyberpunk | $2.99 |
| `afterlap.skin.synthwave` | Synthwave | Cyberpunk | $0.99 |
| `afterlap.skin.eldritch` | Eldritch Eye | Otherworldly | $2.99 |
| `afterlap.skin.starjelly` | Star Jelly | Otherworldly | $1.99 |
| `afterlap.skin.voidwalker` | Voidwalker | Otherworldly | $1.99 |
| `afterlap.skin.qilin` | Qilin | Mythic Beasts | $2.99 |
| `afterlap.skin.hippocamp` | Hippocamp | Mythic Beasts | $1.99 |
| `afterlap.skin.paladin` | Paladin | Legendary Heroes | $2.99 |
| `afterlap.skin.berserker` | Berserker | Legendary Heroes | $1.99 |
| `afterlap.skin.moonoracle` | Moon Oracle | Celestial | $1.99 |
| `afterlap.skin.meteorknight` | Meteor Knight | Celestial | $0.99 |
| `afterlap.skin.plaguedoctor` | Plague Doctor | Dark Fantasy | $1.99 |
| `afterlap.skin.necromancer` | Necromancer | Dark Fantasy | $2.99 |
| `afterlap.skin.frostwarden` | Frost Warden | Elemental Lords | $2.99 |
| `afterlap.skin.galespirit` | Gale Spirit | Elemental Lords | $1.99 |
| `afterlap.skin.glitchqueen` | Glitch Queen | Cyberpunk | $2.99 |
| `afterlap.skin.hoverdrone` | Hover Drone | Cyberpunk | $0.99 |
| `afterlap.skin.crystalwanderer` | Crystal Wanderer | Otherworldly | $1.99 |
| `afterlap.skin.dreamweaver` | Dream Weaver | Otherworldly | $2.99 |
| `afterlap.skin.gulper` | Gulper | Abyssal Depths | $2.99 |
| `afterlap.skin.trenchhorror` | Trench Horror | Abyssal Depths | $1.99 |
| `afterlap.skin.deepdiver` | Deep Diver | Abyssal Depths | $0.99 |
| `afterlap.skin.coralempress` | Coral Empress | Abyssal Depths | $1.99 |
| `afterlap.skin.drownedking` | Drowned King | Abyssal Depths | $2.99 |
| `afterlap.skin.sunpharaoh` | Sun Pharaoh | Ancient Pantheon | $2.99 |
| `afterlap.skin.thunderking` | Thunder King | Ancient Pantheon | $2.99 |
| `afterlap.skin.moonhuntress` | Moon Huntress | Ancient Pantheon | $1.99 |
| `afterlap.skin.jackalguide` | Jackal Guide | Ancient Pantheon | $1.99 |
| `afterlap.skin.harvestgoddess` | Harvest Goddess | Ancient Pantheon | $0.99 |
| `afterlap.skin.automaton` | Brass Automaton | Clockwork Age | $2.99 |
| `afterlap.skin.steambaron` | Steam Baron | Clockwork Age | $1.99 |
| `afterlap.skin.clockheart` | Clock Heart | Clockwork Age | $0.99 |
| `afterlap.skin.skycaptain` | Sky Captain | Clockwork Age | $1.99 |
| `afterlap.skin.timekeeper` | Timekeeper | Clockwork Age | $2.99 |

The game shows Apple's local price (for example in euros) once the app is connected to the store; the USD prices above are only the fallback.

## 3. Test before submitting

1. In App Store Connect: **Users and Access → Sandbox → Testers** → add a test Apple ID.
2. Build to an iPhone from Xcode, open **Skins → Premium**, buy a skin and sign in with the sandbox tester when asked. Sandbox purchases are free.
3. Delete and reinstall the app, then tap **Restore purchases** in the purchase sheet: the skin should come back.

## 4. Submitting

Add the in-app purchases to the app version on its page under **In-App Purchases and Subscriptions** before you send it for review. Apple reviews them with the first version that includes them.

## Adding a premium skin later

1. Add a `PS(...)` line in `src/afterlap.html` (next to the others) and rebuild.
2. Create the matching product here with the ID `afterlap.skin.<id>`.

## Good to know

- Ownership comes from Apple (`Transaction.currentEntitlements`), checked every time the game starts and on Restore. Refunded purchases aren't granted again, but a skin already unlocked on a device stays there (the game never takes skins away).
- The check happens on the device; there is no receipt check on our server. That's normal for cosmetic items, but it means a modified device could unlock them.
- Premium skins never change speed, size or hitbox, and they don't count towards the collection awards.
