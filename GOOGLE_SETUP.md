# Connect Google Calendar (about 10 minutes, once)

Loose Ends uses your **UMich Google account** to:
- see when you and a friend are both free (free/busy only, never event details),
- look up a friend's UMich email by name (your Google directory),
- put the plan on **your** calendar,
- match your contacts to UMich emails from the **From / To / Cc lines** of your mail (never subjects or bodies; the result stays in `data/gmail-people.json` on this Mac).

**No invites go to friends yet.** That's switched off in `lib/google.mjs` (`SEND_INVITES = false`).

## 1. Create the Google credentials
1. Go to <https://console.cloud.google.com/> and sign in with your **umich.edu** account.
2. Top bar → project picker → **New project** → name it `Loose Ends` → Create.
3. **APIs & Services → Library**, and enable all three:
   - Google Calendar API
   - People API
   - Gmail API (headers only: used to match a nickname like "Sammy" to their umich.edu address from people you've emailed)
4. **APIs & Services → OAuth consent screen**: choose **Internal** if it's offered (UMich-only), otherwise External and add yourself as a test user. Fill in the app name and your email, then Save.
5. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Desktop app**
   - Name: `Loose Ends Mac`
   - Create → **Download JSON**.
6. Rename the downloaded file to `google-oauth.json` and put it in this folder:
   `~/Desktop/loose-ends/google-oauth.json`

## 2. Sign in
1. Restart the companion: `npm start` (in `~/Desktop/loose-ends`).
2. On your Mac, open <http://127.0.0.1:4321/auth/google> and sign in with your umich.edu account.
3. You'll see "Google Calendar connected."

If UMich blocks the sign-in ("This app is blocked" / "admin approval required"), that's UMich's Google policy. The app still works without it: plans just default to tomorrow at 7 and nothing goes on your calendar.

## How it shows up
- Each card in the deck gets an evening you're both free (people later in the deck start their search a day later, so plans spread across the week), with that evening's busy times shown as gray blocks. You see "Busy", never what anyone is doing.
- **Swipe right** puts "Kang's with Nat" on **your** calendar at that time, with the place's address as the location. No invite goes to the friend while `SEND_INVITES = false`.
- On the end screen, tap a plan to open its event.

Free/busy for a friend only shows up when their calendar shares free/busy with you (common within umich.edu) and the directory found exactly one person with that name. Otherwise only your own calendar is checked.
