// Reads your real iMessage history from the local Messages database (read-only).
// Requires Full Disk Access for the app running this server (Terminal, iTerm, etc.):
// System Settings → Privacy & Security → Full Disk Access.

import { DatabaseSync } from "node:sqlite";
import { homedir } from "node:os";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const CHAT_DB = join(homedir(), "Library/Messages/chat.db");
const LOOKBACK_DAYS = 60;
const MAX_PEOPLE = 20; // most recently active 1:1 threads
const MAX_MESSAGES = 50; // most recent messages per person

export class IMessageAccessError extends Error {}

// Newer macOS stores message text in an "attributedBody" blob (an NSAttributedString
// typedstream) instead of the plain `text` column. The string sits right after the
// "NSString" class marker, prefixed by a length.
function decodeAttributedBody(blob) {
  if (!blob) return null;
  const buf = Buffer.from(blob);
  const marker = buf.indexOf("NSString");
  if (marker === -1) return null;
  let i = marker + "NSString".length + 5;
  let len = buf[i];
  if (len === 0x81) {
    len = buf.readUInt16LE(i + 1);
    i += 3;
  } else if (len === 0x82) {
    len = buf.readUInt32LE(i + 1);
    i += 5;
  } else {
    i += 1;
  }
  const text = buf.subarray(i, i + len).toString("utf8").trim();
  return text || null;
}

// Best-effort names from the macOS Contacts database. Falls back to the raw handle.
function loadContactNames() {
  const names = new Map();
  const root = join(homedir(), "Library/Application Support/AddressBook");
  const dbs = [];
  const main = join(root, "AddressBook-v22.abcddb");
  if (existsSync(main)) dbs.push(main);
  const sources = join(root, "Sources");
  if (existsSync(sources)) {
    for (const dir of readdirSync(sources)) {
      const p = join(sources, dir, "AddressBook-v22.abcddb");
      if (existsSync(p)) dbs.push(p);
    }
  }
  for (const path of dbs) {
    try {
      const db = new DatabaseSync(path, { readOnly: true });
      const rows = db
        .prepare(
          `SELECT r.ZFIRSTNAME AS first, r.ZLASTNAME AS last, p.ZFULLNUMBER AS phone, NULL AS email
             FROM ZABCDRECORD r JOIN ZABCDPHONENUMBER p ON p.ZOWNER = r.Z_PK
           UNION ALL
           SELECT r.ZFIRSTNAME, r.ZLASTNAME, NULL, e.ZADDRESS
             FROM ZABCDRECORD r JOIN ZABCDEMAILADDRESS e ON e.ZOWNER = r.Z_PK`
        )
        .all();
      for (const row of rows) {
        const name = [row.first, row.last].filter(Boolean).join(" ").trim();
        if (!name) continue;
        if (row.phone) names.set(normalizeHandle(row.phone), name);
        if (row.email) names.set(normalizeHandle(row.email), name);
      }
      db.close();
    } catch {
      // Contacts unreadable: fine, we show handles instead.
    }
  }
  return names;
}

function normalizeHandle(h) {
  if (h.includes("@")) return h.toLowerCase().trim();
  const digits = h.replace(/\D/g, "");
  return digits.slice(-10);
}

export function loadIMessage() {
  if (!existsSync(CHAT_DB)) {
    throw new IMessageAccessError("No Messages database found on this Mac.");
  }
  let db;
  try {
    db = new DatabaseSync(CHAT_DB, { readOnly: true });
    db.prepare("SELECT 1 FROM message LIMIT 1").get();
  } catch {
    throw new IMessageAccessError(
      "Can't read Messages. Give your terminal app Full Disk Access (System Settings → Privacy & Security → Full Disk Access), then restart the server."
    );
  }

  const since = Math.floor(Date.now() / 1000) - LOOKBACK_DAYS * 86400;
  // Apple stores dates as nanoseconds since 2001-01-01 (older DBs: seconds).
  // Convert in SQL so we never touch 64-bit values in JS.
  const rows = db
    .prepare(
      `SELECT c.chat_identifier AS handle,
              m.text AS text,
              m.attributedBody AS body,
              m.is_from_me AS fromMe,
              (CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200 AS unix
         FROM message m
         JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
         JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.style = 45                      -- 1:1 chats only, no group chats
          AND m.associated_message_type = 0     -- skip tapbacks/reactions
          AND (CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200 > ?
        ORDER BY unix ASC`
    )
    .all(since);
  db.close();

  const byHandle = new Map();
  for (const r of rows) {
    const text = (r.text && r.text.trim()) || decodeAttributedBody(r.body);
    if (!text || text === "￼") continue; // attachments only
    if (!byHandle.has(r.handle)) byHandle.set(r.handle, []);
    byHandle.get(r.handle).push({
      at: new Date(Number(r.unix) * 1000).toISOString(),
      fromMe: Boolean(r.fromMe),
      text,
    });
  }

  const names = loadContactNames();
  const threads = [...byHandle.entries()]
    // Short codes (banks, 2FA, delivery) aren't people.
    .filter(([handle]) => handle.includes("@") || handle.replace(/\D/g, "").length >= 10)
    .map(([handle, messages]) => ({
      id: "im-" + normalizeHandle(handle),
      name: names.get(normalizeHandle(handle)) || handle,
      handle,
      sample: false,
      messages: messages.slice(-MAX_MESSAGES),
    }))
    .sort((a, b) => b.messages.at(-1).at.localeCompare(a.messages.at(-1).at))
    .slice(0, MAX_PEOPLE);

  return threads;
}

// People you used to text a lot but haven't in a while (looks back a year, counts only).
// Used for "Haven't talked in a while" once tonight's list is done.
export function loadQuietContacts({ minDays = 14, limit = 4 } = {}) {
  let db;
  try {
    db = new DatabaseSync(CHAT_DB, { readOnly: true });
  } catch {
    return [];
  }
  const since = Math.floor(Date.now() / 1000) - 365 * 86400;
  const rows = db
    .prepare(
      `SELECT c.chat_identifier AS handle,
              COUNT(*) AS n,
              SUM(m.is_from_me) AS mine,
              MAX((CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200) AS last
         FROM message m
         JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
         JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.style = 45 AND m.associated_message_type = 0
          AND (CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200 > ?
        GROUP BY c.chat_identifier`
    )
    .all(since);
  db.close();
  const names = loadContactNames();
  const now = Date.now() / 1000;
  return rows
    .map((r) => ({
      handle: r.handle,
      key: normalizeHandle(r.handle),
      n: Number(r.n),
      mine: Number(r.mine),
      daysQuiet: Math.floor((now - Number(r.last)) / 86400),
    }))
    // Real contacts you had a two-way conversation with, now quiet.
    .filter((r) => names.has(r.key) && r.daysQuiet >= minDays && r.mine >= 5 && r.n - r.mine >= 5)
    .map((r) => ({ ...r, name: names.get(r.key), score: Math.log(r.n) * Math.min(1, r.daysQuiet / 60) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((r) => ({ id: `im-${r.key}:quiet`, personId: `im-${r.key}`, name: r.name, handle: r.handle, daysQuiet: r.daysQuiet }));
}

// ---------- Reach out: friends you text but haven't made plans with ----------
// Signals (last 6 months, 1:1 chats with saved contacts):
//  • steady: texted in many different weeks, including the last month (not someone you stopped talking to)
//  • two-way: both of you write (not one-sided, not a business)
//  • planless: long time since either of you suggested meeting up (dinner, coffee, hang, free sat, etc.)
// Old dates and lapsed contacts drop out because they aren't texting you regularly now.
const PLAN_RE = /\b(hang( ?out)?|grab (food|lunch|dinner|coffee|a bite|drinks?)|get (food|lunch|dinner|coffee|drinks?|boba)|(lunch|dinner|brunch|coffee|boba|drinks|movie|pregame|party|gym|study) (tmrw|tomorrow|tonight|today|this week(end)?|on \w+day|sat|sun|fri)|wanna (go|come|get|grab|hang|meet)|let'?s (go|get|grab|hang|meet|do)|meet up|are (u|you) free|when are (u|you) free|free (tmrw|tomorrow|tonight|this weekend|sat|sun|fri)|see (u|you) (tmrw|tomorrow|tonight|soon|sat|sun|fri|at)|come over|pull up|link up)\b/i;
const FAMILY_RE = /\b(mom|mum|dad|mother|father|grandma|grandpa|nana|papa|aunt|uncle)\b|妈|爸/i;
const WEEK = 7 * 86400;
// Your own number(s), from MY_NUMBER in .env: notes-to-self aren't a friend. (Read lazily: .env loads after imports.)
const selfNumbers = () => new Set((process.env.MY_NUMBER || "").split(",").map((n) => n.replace(/\D/g, "").slice(-10)).filter(Boolean));

// Your corrections, by contact name: always suggest (pinned), never suggest (blocked).
function loadOverrides() {
  try { return JSON.parse(readFileSync(new URL("../data/reach-overrides.json", import.meta.url), "utf8")); }
  catch { return { pinned: [], blocked: [], aliases: {} }; }
}

export function loadReachOut({ exclude = new Set(), limit = 5, debug = false } = {}) {
  const ov = loadOverrides();
  const pinned = new Set(ov.pinned || []), blocked = new Set(ov.blocked || []);
  let db;
  try { db = new DatabaseSync(CHAT_DB, { readOnly: true }); } catch { return []; }
  const now = Date.now() / 1000;
  const since = Math.floor(now) - 182 * 86400;
  const rows = db
    .prepare(
      `SELECT c.chat_identifier AS handle, m.text AS text, m.attributedBody AS body, m.is_from_me AS fromMe,
              (CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200 AS unix
         FROM message m
         JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
         JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.style = 45 AND m.associated_message_type = 0
          AND (CASE WHEN m.date > 100000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200 > ?`
    )
    .all(since);
  db.close();

  const names = loadContactNames();
  const people = new Map();
  for (const r of rows) {
    const key = normalizeHandle(r.handle);
    if (!names.has(key)) continue;
    let p = people.get(key);
    if (!p) people.set(key, (p = { key, handle: r.handle, n: 0, mine: 0, weeks: new Set(), last: 0, lastPlan: 0 }));
    const t = Number(r.unix);
    p.n++;
    if (r.fromMe) p.mine++;
    p.weeks.add(Math.floor((now - t) / WEEK));
    p.last = Math.max(p.last, t);
    const text = (r.text && r.text.trim()) || (r.body ? decodeAttributedBody(r.body) : "");
    if (text && PLAN_RE.test(text)) p.lastPlan = Math.max(p.lastPlan, t);
  }

  const all = [...people.values()]
    .map((p) => {
      const name = names.get(p.key);
      const theirs = p.n - p.mine;
      const activeWeeks = p.weeks.size;                       // out of ~26
      const daysSinceText = (now - p.last) / 86400;
      const daysSincePlan = p.lastPlan ? (now - p.lastPlan) / 86400 : 182;
      const balance = Math.min(p.mine, theirs) / Math.max(p.mine, theirs, 1); // 1 = even back-and-forth
      return { ...p, name, theirs, activeWeeks, daysSinceText, daysSincePlan, balance };
    });
  if (debug) return all;
  const pins = all.filter((p) => pinned.has(p.name) && !exclude.has(`im-${p.key}`));
  return pins.map((p) => ({ ...p, score: 10 })).concat(all
    .filter((p) => !pinned.has(p.name) && !blocked.has(p.name))
    .filter((p) =>
      !exclude.has(`im-${p.key}`) &&
      !selfNumbers().has(p.key) &&
      !FAMILY_RE.test(p.name) &&
      p.activeWeeks >= 6 &&          // texts semi-regularly
      p.daysSinceText <= 30 &&       // still in touch now
      p.mine >= 10 && p.theirs >= 10 &&
      p.balance >= 0.35 &&
      p.daysSincePlan >= 30          // but no plans in a month+
    )
    .map((p) => ({
      ...p,
      score: Math.min(1, p.activeWeeks / 16) * (0.5 + 0.5 * p.balance) * Math.min(1, p.daysSincePlan / 90),
    }))
  )
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((p) => ({
      id: `im-${p.key}:reach`,
      personId: `im-${p.key}`,
      name: p.name,
      handle: p.handle,
      daysQuiet: Math.round(p.daysSincePlan),
      activeWeeks: p.activeWeeks,
    }));
}
