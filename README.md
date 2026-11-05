# Loose Ends

An iPhone app that turns the friends you keep meaning to see into plans.

Each week it finds the people you text all the time but haven't actually made plans with, drafts the text, finds an evening you're both free, and picks a spot near campus. You swipe through them like a deck: right to make the plan, left to skip.

**[Try the web demo](sandbox/demo.html)** (made-up people and plans; nothing is sent).

## What it does

- **A deck of plans.** Each card has a friend, a drafted text you can edit in place, and their evening on a small calendar: your busy times and theirs (free/busy only), with the plan blocked in.
- **Tap the plan to flip it** to another place within walking distance of the Diag: State Street and South University restaurants, or a hangout ("study at Hatcher", "lock in at the Dude"). The text rewrites itself to match.
- **Hold and drag the plan to change the time.** The day scrolls as you drag. Over a busy block the plan turns red, and if you let go there it slides back.
- **Swipe right** to put the plan on your Google Calendar, with the place's address, and send the text. Emoji confetti matches the plan (🍲 for Kang's, 📚 for Hatcher).
- **End of the week:** the plans you made, each as a card. Tap one to open its calendar event.
- **Next week:** pick who you want to see. On Monday a Live Activity on the lock screen reminds you ("Make plans with Ruby, Omar and Hana this week"), and the deck has their plans ready.
- **After you make a plan**, the Dynamic Island shows who and when for 20 seconds.

## Why there's a Mac part

iPhone apps can't read iMessages. Your Mac can, because iMessage syncs there. So a small companion on the Mac reads your messages and your Google Calendar and sends the phone only what it needs:

```
Mac companion (iMessage + Google Calendar)  ──►  iPhone app (deck, lock screen)  ──►  your calendar + Messages
```

## How it picks people

From the last 6 months of 1:1 texts, someone is suggested when all of these are true:

- **Steady:** you've texted in at least 6 different weeks, including the last month.
- **Two-way:** you both write (at least 10 messages each, reasonably balanced), so not a business or a one-sided thread.
- **No plans lately:** neither of you has suggested meeting up ("grab dinner", "are you free", "let's get…") in 30+ days.

Family, group chats and your own number are skipped. You can pin or block people in `data/reach-overrides.json`.

## Privacy

- Messages are read on your Mac and stay there. The phone gets first names and drafted texts, never your message history.
- Calendars are read as **free/busy only**, so you see "Busy", never what someone is doing.
- While the app is in test mode, texts go **only to your own number** (`TEST_RECIPIENT` in `.env`), and calendar events go on **your** calendar with no invites sent (`SEND_INVITES = false` in `lib/google.mjs`).

## Run it

**Mac companion**

1. System Settings → Privacy & Security → **Full Disk Access** → turn on **Terminal** (needed to read Messages).
2. Create `.env` in this folder:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   TEST_RECIPIENT=+1XXXXXXXXXX   # your own number: test texts only go here
   MY_NUMBER=XXXXXXXXXX          # so notes-to-self aren't counted as a friend
   ```
3. For Google Calendar, follow [GOOGLE_SETUP.md](GOOGLE_SETUP.md).
4. In **Terminal** (not an editor's built-in terminal, which won't have Full Disk Access):
   ```bash
   npm install
   HOST=0.0.0.0 PAIR_CODE=123456 npm start
   ```
   `HOST=0.0.0.0` lets your phone connect over Wi-Fi; the pairing code keeps anyone else on the network out.

**iPhone app**

1. Copy `ios/Secrets.example.swift` to `ios/LooseEnds/Secrets.swift` and put in your number.
2. `cd ios && xcodegen generate`, then open `LooseEnds.xcodeproj`. Set your Team in `project.yml` (`DEVELOPMENT_TEAM`) or under Signing & Capabilities for both targets.
3. Pick your iPhone and press Run. The first time, trust the developer under Settings → General → VPN & Device Management.
4. In the app, long-press **This week** to open Settings. Set the Mac address to `http://<your Mac's IP>:4321` and enter the pairing code. Your phone and Mac need to be on the same network.

Settings also has demo controls: skip to next week, show the lock-screen card, remind me of today's plans, test confetti, and start the week over.

## Code

- `server.mjs`: the Mac companion's API (`/api/digest`, `/api/plan`, `/api/test-send`)
- `lib/imessage.mjs`: reads `chat.db` (read-only) and Contacts names; the reach-out picks
- `lib/google.mjs`: Google sign-in, free/busy slots, creating the event, matching friends to emails
- `lib/analyze.mjs`, `lib/rank.mjs`: earlier nightly-digest logic, still used for the message read
- `ios/LooseEnds`: the SwiftUI app. `PlanDeckView` (screens), `DeckCard` (card, calendar, flip and drag), `PlanDeck` (places, deck state), `Confetti`, `PlansActivity` (Live Activity)
- `ios/LooseEndsWidget`: the lock-screen Live Activity and Dynamic Island
- `sandbox/demo.html`: the browser demo
