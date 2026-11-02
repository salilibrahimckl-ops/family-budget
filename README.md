# Family Budget: setup guide

One app for both phones. You both share one family pool, and the app also tracks what each person spends.

- **Android:** reads bank SMS by itself, even when the app is closed.
- **iPhone:** Apple doesn't let apps read SMS, so a Shortcuts automation forwards each bank SMS to the app.
- Payees are sorted into Food, Grocery, Travel, Shopping, Fun, Chitti, Savings or Other. Tag a payee once and the app uses that category for it from then on.
- **Chitti:** when the same amount (₹500 or more) goes to the same payee in two different months, or the payee name looks like a chit fund (KSFE, kuri, chitty), the app asks *"Is this your chitti?"* If you answer Yes, that payment and the earlier ones with the same amount move to Chitti, and later payments go there automatically. If you answer No, the app stops asking about that payee.

The whole setup takes about an hour, done once on your Mac.

---

## 1. Install the tools on your Mac

```bash
# Homebrew (skip if you already have it): https://brew.sh
brew install --cask flutter
brew install cocoapods
```
- **Xcode:** install it from the Mac App Store, open it once, and accept the licence.
- **Android Studio:** install it from https://developer.android.com/studio, open it once, and let it download the Android SDK. Then run:
```bash
flutter doctor --android-licenses   # answer y to everything
flutter doctor                      # Android toolchain and Xcode should show ✓
```

## 2. Create the free cloud database (Firebase)

1. Go to https://console.firebase.google.com and click **Create a project**. Name it something like `family-budget` and turn Google Analytics off.
2. Open **Build → Authentication → Get started**. On the **Sign-in method** tab, choose **Anonymous** and turn on **Enable**.
3. Open **Build → Firestore Database → Create database**. Pick the location **asia-south1 (Mumbai)** and choose **Start in production mode**.
4. In Firestore, open the **Rules** tab. Replace everything with the contents of `src/firestore.rules` and click **Publish**.
5. Click ⚙️ **Project settings**, then under **Your apps** click the **`</>` (Web)** icon. Register an app called `family-budget` (you don't need hosting).
6. Firebase now shows a block like the one below. Copy the whole block and send it to your phone, for example by WhatsApp to yourself:
   ```js
   const firebaseConfig = {
     apiKey: "AIza…",
     authDomain: "…",
     projectId: "family-budget-xxxx",
     storageBucket: "…",
     messagingSenderId: "1234…",
     appId: "1:1234…:web:abcd…"
   };
   ```

The free Spark plan is more than enough for a family.

## 3. Build the app

```bash
cd family_budget
bash setup.sh
```
This builds the project, runs the SMS-parser tests, and creates **`FamilyBudget.apk`**.

## 4. Your Android phone

1. Copy `FamilyBudget.apk` to your phone (Google Drive, a USB cable or WhatsApp) and install it. If Play Protect warns you, tap **Install anyway**.
2. **Android 13 or later:** Android blocks SMS access for apps installed outside the Play Store. If the SMS permission is greyed out or refused, go to **Settings → Apps → Family Budget → ⋮ (top right) → Allow restricted settings** and open the app again.
3. Open the app and tap **Create family**. Enter your name, paste the Firebase block from step 2, and tap **Create**.
4. Allow **SMS** access. The app imports this month's bank SMS right away.
5. On the **Budget** tab, enter monthly amounts for each category. You can also set a personal limit for each person, which shows as their "balance". The same budget carries over to later months automatically.
6. Go to **Settings → Invite your family → copy** and send the code to your wife.

## 5. Your wife's iPhone

**Install with a free Apple ID.** The app needs reinstalling every 7 days. A paid developer account ($99/year) removes this limit.

1. Connect the iPhone to the Mac with a cable. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** (it restarts).
2. On the Mac: `open family_budget/app/ios/Runner.xcworkspace`
3. In Xcode, click **Runner** (left panel), then **Signing & Capabilities**:
   - **Team:** click Add Account and sign in with your Apple ID, then pick "(Personal Team)".
   - **Bundle Identifier:** change it to something unique, such as `com.salil.familybudget`.
4. At the top, pick her iPhone as the device and press ▶ Run.
5. On the iPhone, go to **Settings → General → VPN & Device Management**, tap your Apple ID, and choose **Trust**.
6. Open the app and tap **Join family**. Enter her name, paste the invite code, and tap **Join**.

To renew every 7 days, plug the iPhone in and press ▶ again (or run `cd app && flutter run --release`). The data lives in the cloud, so nothing is lost.

## 6. iPhone: forward bank SMS automatically (once, about 5 minutes)

1. In the app on her iPhone, go to **Settings → iPhone automation** and tap copy to copy the URL.
2. Open the **Shortcuts** app and go to **Automation → + → Message**.
   - Under **Message Contains**, type `debited`. (HDFC and Kotak messages say "Sent" instead, so set up a second automation for `Sent` if she banks with them.)
   - Choose **Run Immediately**, then **Next → New Blank Automation**.
3. Add the action **Get Contents of URL**:
   - **URL:** paste the copied URL.
   - Tap **Show More**, then set **Method:** `POST` and **Request Body:** `JSON`.
   - **Add new field → Dictionary**, key `fields`
     - inside it: **Add new field → Dictionary**, key `text`
       - inside that: **Add new field → Text**, key `stringValue`. For the value, tap it and pick the **Shortcut Input** variable (the message).
4. Tap **Done**.

From then on, every bank SMS she gets is sent to the family. Either phone turns it into a payment the next time the app is open. This needs iOS 17 or later.

## Everyday use

- **Overview:** shows how much is left this month in the family pool, each category, and each person's spending and balance.
- **Red "needs a category" card:** payments to new payees, such as a person's name. Tap a payment and pick a category. The app uses that category for that payee from then on, unless you untick the box.
- **"Is this your chitti?" card:** answer once per chit fund.
- **Charts on Overview:** a ring chart shows what each category has used and what is left. Bar charts show spent against budget for each category and spending for each day of the month. The dashed line marks the daily amount that keeps you on budget.
- **Add spending:** the button at the bottom of Overview adds a cash payment, or any payment the SMS reading missed.
- **Settings → Developer options:** create your own categories, such as Medical or School fees. You can name each one, pick an icon and colour, and add keywords (for example `apollo, pharmacy`) so matching payments go there automatically. You can also rename or hide the built-in categories.
- **Payments tab:** filter by person or category. Tap a payment to change its category or amount, add a note, or mark it as **Not a spend** (for example a transfer to your own account).
- **+ Cash / other:** add cash payments yourself.

## Troubleshooting

| Problem | Fix |
|---|---|
| `setup.sh` fails at `pub add` or build | Run `flutter upgrade` and try again. If it still fails, send Claude the error text. |
| Create or Join says "permission denied" | Check that Anonymous sign-in is enabled (step 2.2) and the rules are published (step 2.4). |
| An SMS was missed on Android | Go to **Settings → Re-scan this month**. Payments already added are skipped. |
| Your bank's SMS isn't picked up | Send Claude the SMS text with the account number hidden, and it can add that format. |
| iPhone app stops opening after a week | The free signing expired. Press ▶ in Xcode again. |
