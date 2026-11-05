// Loose Ends Mac companion.
// Reads your real iMessages (iPhones can't), finds the loose ends, and serves them
// to the Loose Ends iPhone app. Nothing is ever sent from here: the phone opens
// Messages with the draft typed in, and you hit send.

import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { execFile } from "node:child_process";
import { loadIMessage, loadQuietContacts, loadReachOut, IMessageAccessError } from "./lib/imessage.mjs";
import { analyzeAll, hasApiKey, MODEL } from "./lib/analyze.mjs";
import { rank, loadState, saveState } from "./lib/rank.mjs";
import * as google from "./lib/google.mjs";

// Tiny .env loader so you can drop ANTHROPIC_API_KEY=... in a file.
const envPath = new URL("./.env", import.meta.url).pathname;
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

const PORT = Number(process.env.PORT || 4321);
// Default: only this Mac (and the iOS Simulator) can connect.
// HOST=0.0.0.0 lets your phone connect over Wi-Fi, and then a pairing code is required,
// so nobody else on the network can read your loose ends.
const HOST = process.env.HOST || "127.0.0.1";
const LAN = HOST !== "127.0.0.1" && HOST !== "localhost";
const CODE = process.env.PAIR_CODE || randomBytes(3).toString("hex");

function json(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

// Plan-making drafts: the point is to actually see them, not just say hi.
const HELLOS = [
  "we should get dinner this week!! when are u free",
  "wanna grab coffee or boba sometime this week?",
  "it's been forever since we hung out!! free this weekend?",
  "let's do something soon!! lunch this week?",
  "we need to catch up fr, are u free sat?",
];
function quietList(exclude) {
  const state = loadState();
  return loadReachOut({ exclude, limit: 8 })
    .filter((q) => {
      const p = state.people[q.personId];
      if (p?.action === "not_close") return false;
      return !(p?.action === "sent" && Date.now() - new Date(p.at).getTime() < 0.8 * 86400000);
    })
    .map((q, i) => ({ ...q, draft: HELLOS[i % HELLOS.length] }));
}

async function digest({ refresh }) {
  const threads = loadIMessage();
  const engine = hasApiKey() ? "claude" : "offline";
  const { results, errors } = await analyzeAll(threads, { engine, refresh });
  const ranked = rank(results, loadState());
  return {
    engine,
    model: engine === "claude" ? MODEL : null,
    generatedAt: new Date().toISOString(),
    stats: {
      people: threads.length,
      messages: threads.reduce((n, t) => n + t.messages.length, 0),
      looseEnds: results.reduce((n, r) => n + (r.analysis.is_personal ? r.analysis.loose_ends.length : 0), 0),
      overflow: ranked.overflow,
      snoozed: ranked.snoozed,
      handled: ranked.handled,
    },
    cards: ranked.cards.map((c) => ({ ...c, also: c.also.map((l) => l.label) })),
    quiet: quietList(new Set(ranked.cards.map((c) => c.personId))),
    errors,
  };
}

// Test sends go through this Mac's Messages app, and ONLY to your own number.
// The phone can't choose the recipient, so a bug can never text a real friend.
const TEST_RECIPIENT = process.env.TEST_RECIPIENT || "";   // your own number, set in .env (never a friend)
const SEND_SCRIPT = `
on run argv
  tell application "Messages"
    set svc to 1st account whose service type = iMessage
    send (item 2 of argv) to participant (item 1 of argv) of svc
  end tell
end run`;

function sendToSelf(text) {
  return new Promise((resolve, reject) => {
    execFile("osascript", ["-e", SEND_SCRIPT, TEST_RECIPIENT, text], (err, _out, stderr) =>
      err ? reject(new Error(stderr.trim() || err.message)) : resolve()
    );
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  // This Mac (and the Simulator) never needs the code; anything else on the Wi-Fi does.
  const local = ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(req.socket.remoteAddress);
  if (LAN && !local && req.headers["x-pair-code"] !== CODE) return json(res, 401, { error: "Wrong pairing code." });
  try {
    // ---- Google Calendar ----
    if (url.pathname === "/auth/google") {
      const to = google.authUrl();
      if (!to) return json(res, 400, { error: "Put google-oauth.json in the loose-ends folder first (see GOOGLE_SETUP.md)." });
      res.writeHead(302, { location: to }); return res.end();
    }
    if (url.pathname === "/auth/google/callback") {
      try {
        await google.finishAuth(url.searchParams.get("code"));
        res.writeHead(200, { "content-type": "text/html" });
        return res.end("<body style='font:20px -apple-system;padding:48px;background:#000;color:#fff'>Google Calendar connected. You can close this tab.</body>");
      } catch (e) { return json(res, 400, { error: e.message }); }
    }
    if (url.pathname === "/api/google/status") return json(res, 200, google.status());
    if (url.pathname === "/api/google/scan-calendar" && req.method === "POST") {
      if (!local) return json(res, 403, { error: "Run the calendar scan from this Mac." });
      return json(res, 200, await google.scanCalendar());
    }
    if (url.pathname === "/api/google/scan-gmail" && req.method === "POST") {
      // Your own Mac, your own mail: headers only, results stay in data/gmail-people.json.
      if (!local) return json(res, 403, { error: "Run the Gmail scan from this Mac." });
      return json(res, 200, await google.scanGmail());
    }
    if (url.pathname === "/api/plan" && req.method === "GET") {
      // A free evening slot with this person, and the text that goes with it.
      if (!google.status().connected) return json(res, 200, { connected: false });
      const name = url.searchParams.get("name") || "";
      const first = name.split(" ")[0];
      const email = await google.guessEmail(name).catch(() => null);
      const slot = await google.findSlot(email, Math.max(0, Math.min(6, Number(url.searchParams.get("day")) || 0)));
      if (!slot) return json(res, 200, { connected: true, email, slot: null });
      const s = new Date(slot.start);
      const day = s.toLocaleDateString("en-US", { weekday: "short" }).toLowerCase();
      const time = s.toLocaleTimeString("en-US", { hour: "numeric" }).toLowerCase().replace(" ", "");
      const label = s.toLocaleDateString("en-US", { weekday: "short" }) + " " + s.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
      return json(res, 200, { connected: true, email, slot, label, bothFree: slot.bothFree, busy: slot.busy,
        draft: `wanna get dinner ${day} at ${time}?? i put it on my cal`, title: `Dinner with ${first}` });
    }
    if (url.pathname === "/api/plan" && req.method === "POST") {
      const { title, start, end, email, location } = await readBody(req);
      const ev = await google.createPlan({ title, start, end, friendEmail: email, location });
      return json(res, 200, { ok: true, link: ev.htmlLink, invited: google.status().invites && !!email });
    }

    if (url.pathname === "/api/digest") {
      return json(res, 200, await digest({ refresh: url.searchParams.get("refresh") === "1" }));
    }

    if (url.pathname === "/api/test-send" && req.method === "POST") {
      if (!TEST_RECIPIENT) return json(res, 400, { error: "Set TEST_RECIPIENT (your own number) in .env to test sends." });
      const { text } = await readBody(req);
      if (typeof text !== "string" || !text.trim() || text.length > 1000) return json(res, 400, { error: "bad text" });
      try {
        await sendToSelf(text);
        return json(res, 200, { ok: true, to: TEST_RECIPIENT });
      } catch (err) {
        return json(res, 502, {
          error: "Your Mac couldn't send it. Make sure Messages is signed in, and allow the Automation prompt if one appeared.",
          detail: err.message,
        });
      }
    }

    if (url.pathname === "/api/action" && req.method === "POST") {
      const { id, personId, action, draft, days } = await readBody(req);
      const state = loadState();
      const at = new Date().toISOString();
      if (action === "undo") {
        delete state.loops[id];
        delete state.people[personId];
      } else if (action === "not_close") {
        state.people[personId] = { action, at };
      } else if (action === "snooze") {
        state.loops[id] = { action, at, until: new Date(Date.now() + (days || 1) * 86400000).toISOString() };
      } else if (action === "send") {
        state.loops[id] = { action: "sent", draft, at };
        // One text closes the person for tonight, even if they had a second loose end.
        state.people[personId] = { action: "sent", at };
      } else {
        return json(res, 400, { error: "unknown action" });
      }
      saveState(state);
      return json(res, 200, { ok: true });
    }

    json(res, 404, { error: "not found" });
  } catch (err) {
    if (err instanceof IMessageAccessError) return json(res, 403, { error: err.message, kind: "imessage" });
    console.error(err);
    json(res, 500, { error: err.message });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Loose Ends companion on http://${HOST}:${PORT}`);
  console.log(hasApiKey() ? `AI: ${MODEL}` : "No ANTHROPIC_API_KEY in .env: using offline keyword rules.");
  if (LAN) console.log(`Phone pairing code: ${CODE}`);
});
