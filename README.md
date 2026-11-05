# Loose Ends

Every night your phone tells you who you're letting slip, like "3 people worth a text tonight." Tap the notification to see each person, the exact text that proves it, and a draft written the way you text them. **Send** opens Messages with the draft typed in. You always hit send yourself.

## Why there's a Mac part

iPhone apps aren't allowed to read iMessages. Your Mac can, because iMessage syncs there. So:

```
Mac companion (reads chat.db, Claude finds loose ends)  ──►  iPhone app (notification + cards)  ──►  Messages
```

## 1. Start the Mac companion

1. **Full Disk Access:** System Settings → Privacy & Security → Full Disk Access → turn on **Terminal** (or whichever terminal app you use).
2. **API key:** create `~/Desktop/loose-ends/.env` containing:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```
3. In **Terminal**:
   ```bash
   cd ~/Desktop/loose-ends && npm install && npm start
   ```
   You should see `AI: claude-opus-5-5`. The first read of your texts takes about 30–60 seconds. After that it's cached for the day.

## 2a. Run the iPhone app in the Simulator (for the demo video)

```bash
open ~/Desktop/loose-ends/ios/LooseEnds.xcodeproj
```
Pick an iPhone simulator and press ▶. It connects to `http://localhost:4321` automatically.

- **Notification demo:** ⚙️ → **Preview tonight's notification** → press ⌘L to lock the simulator. The banner shows up on the lock screen in 5 seconds.
- The Simulator has no Messages app, so Send copies the draft instead. On a real phone it opens Messages.

## 2b. Run it on your real iPhone (for the demo)

Quick version: see "Phone demo checklist" at the bottom.

## 2b (details). Run it on your real iPhone

1. Plug in your phone. In Xcode: select the **LooseEnds** target → Signing & Capabilities → Team → your Apple ID. Pick your phone as the run destination, then press ▶. (A free Apple ID works. The app expires after 7 days. Just run it again.)
2. On your iPhone: Settings → General → VPN & Device Management → trust your developer certificate.
3. Restart the companion so the phone can reach it over Wi-Fi:
   ```bash
   cd ~/Desktop/loose-ends && HOST=0.0.0.0 npm start
   ```
   It prints a **pairing code**. Without the code, nobody else on the Wi-Fi can read your loose ends.
4. In the app: ⚙️ → set the Mac address to `http://<your-mac-name>.local:4321` (your Mac's name is under System Settings → General → Sharing), then enter the pairing code.

Your phone and Mac need to be on the same Wi-Fi when the app refreshes. The nightly notification fires at 9pm (changeable in ⚙️) using the names from the last refresh.

## Test checklist

- [ ] The cards are real loose ends from your texts, not false alarms. Note any misses. They're good material for the video.
- [ ] Group chats, 2FA codes, and businesses never show up.
- [ ] The drafts sound like you.
- [ ] The ⓘ button shows why each person ranked where they did.
- [ ] Send, Later, and Not close each remove the card. Undo brings it back.
- [ ] After you clear everything, the "all caught up" screen shows.
- [ ] The notification preview shows real names on the lock screen.

## Privacy

Only your 20 most recent 1:1 threads (last 60 days, last 50 messages each) are sent to Claude. Group chats and short codes are skipped. The phone gets only tonight's cards, never your full message history.

## Code

- `server.mjs`: the Mac companion API (`/api/digest`, `/api/action`)
- `lib/imessage.mjs`: reads `chat.db` (read-only) and Contacts names
- `lib/analyze.mjs`: Claude prompt + schema, plus offline keyword fallback
- `lib/rank.mjs`: scoring, the 3-per-night cap, snooze/sent/not-close
- `ios/`: the SwiftUI app (`xcodegen generate` rebuilds the project from `project.yml`)

## Phone demo checklist

**On your iPhone, once:**
1. Plug the iPhone into your Mac with a cable, and tap **Trust This Computer**.
2. Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).

**In Xcode, once:**
3. `open ~/Desktop/loose-ends/ios/LooseEnds.xcodeproj`
4. Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
5. Click the **LooseEnds** project → **Signing & Capabilities** → Team: pick your name.
6. At the top, choose **your iPhone** as the run destination → press **▶**.
7. If the phone says "Untrusted Developer": Settings → General → VPN & Device Management → your Apple ID → **Trust**. Then press ▶ again.

**Start the companion so the phone can reach it (Terminal):**
```bash
cd ~/Desktop/loose-ends && HOST=0.0.0.0 npm start
```
Phone and Mac must be on the same Wi-Fi.

**In the app on your phone:** ⚙️ →
- Mac address: `http://<your-mac-name>.local:4321`
- Pairing code: the `PAIR_CODE` in your `.env` file
- Allow **Local Network** when asked. Pull down to refresh.

Test mode stays on, so Send still texts only you.

**Recording the demo:** QuickTime Player → File → **New Movie Recording** → click the ⌄ next to the record button → pick your iPhone as the camera. That records the phone's real screen, including the lock-screen notification. (iPhone Mirroring can't show the lock screen.)
