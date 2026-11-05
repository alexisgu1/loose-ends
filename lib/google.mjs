// Google Calendar for Loose Ends: sign in once (your UMich Google account), then
//  • find an evening when you and a friend are both free (free/busy only, no event details), and
//  • put the plan on YOUR calendar. Invites to friends are OFF until you turn them on.
// Friends' emails are guessed by searching your Google Workspace directory (UMich) by name.

import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("../", import.meta.url).pathname;
const DATA_DIR = join(ROOT, "data");
const CLIENT_FILE = join(ROOT, "google-oauth.json");   // downloaded from Google Cloud (Desktop app client)
const TOKEN_FILE = join(DATA_DIR, "google-token.json");
const DIR_CACHE = join(DATA_DIR, "directory.json");

// Safety switch, same idea as TestMode.sendTexts in the app: no invites go out while false.
export const SEND_INVITES = false;

export const REDIRECT = "http://127.0.0.1:4321/auth/google/callback";
const SCOPES = [
  "https://www.googleapis.com/auth/calendar.freebusy",        // when people are busy, nothing else
  "https://www.googleapis.com/auth/calendar.events",          // create the plan on your calendar
  "https://www.googleapis.com/auth/directory.readonly",       // look up a friend's UMich email by name
  "https://www.googleapis.com/auth/gmail.metadata",           // email headers only (who, not what)
].join(" ");

function client() {
  if (!existsSync(CLIENT_FILE)) return null;
  const j = JSON.parse(readFileSync(CLIENT_FILE, "utf8"));
  return j.installed || j.web || null;
}
function loadToken() {
  try { return JSON.parse(readFileSync(TOKEN_FILE, "utf8")); } catch { return null; }
}
function saveToken(t) {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(TOKEN_FILE, JSON.stringify(t, null, 2));
  chmodSync(TOKEN_FILE, 0o600);
}

export function status() {
  return { configured: !!client(), connected: !!loadToken()?.refresh_token, invites: SEND_INVITES };
}

export function authUrl() {
  const c = client();
  if (!c) return null;
  const q = new URLSearchParams({
    client_id: c.client_id, redirect_uri: REDIRECT, response_type: "code",
    scope: SCOPES, access_type: "offline", prompt: "consent",
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${q}`;
}

export async function finishAuth(code) {
  const c = client();
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, client_id: c.client_id, client_secret: c.client_secret, redirect_uri: REDIRECT, grant_type: "authorization_code" }),
  });
  const t = await r.json();
  if (!r.ok) throw new Error(t.error_description || t.error || "Google sign-in failed");
  saveToken({ ...t, expires_at: Date.now() + (t.expires_in - 60) * 1000 });
}

async function accessToken() {
  const t = loadToken();
  if (!t?.refresh_token) throw new Error("Google Calendar isn't connected yet.");
  if (t.access_token && Date.now() < t.expires_at) return t.access_token;
  const c = client();
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ refresh_token: t.refresh_token, client_id: c.client_id, client_secret: c.client_secret, grant_type: "refresh_token" }),
  });
  const n = await r.json();
  if (!r.ok) throw new Error(n.error_description || n.error || "Couldn't refresh Google sign-in");
  saveToken({ ...t, access_token: n.access_token, expires_at: Date.now() + (n.expires_in - 60) * 1000 });
  return n.access_token;
}

async function gapi(url, { method = "GET", body } = {}) {
  const r = await fetch(url, {
    method,
    headers: { authorization: `Bearer ${await accessToken()}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error?.message || `Google error ${r.status}`);
  return j;
}

// ---------- Gmail: learn friends' UMich emails from who you've emailed ----------
// Reads only the From / To / Cc headers of your recent mail (never subjects or bodies), and keeps
// "Jane Doe <jdoe@umich.edu>"-style pairs. Saved locally so it only runs once.
const GMAIL_CACHE = join(DATA_DIR, "gmail-people.json");
const norm = (s) => s.toLowerCase().replace(/\(.*?\)/g, "").replace(/[^a-z ]/g, "").replace(/(.)\1+$/, "$1").trim();

export async function scanGmail({ max = 1500 } = {}) {
  const seen = {};   // email -> { name, count }
  let pageToken = "", ids = [];
  while (ids.length < max) {
    const q = new URLSearchParams({ maxResults: "500", ...(pageToken ? { pageToken } : {}) });
    const j = await gapi(`https://gmail.googleapis.com/gmail/v1/users/me/messages?${q}`);
    ids.push(...(j.messages || []).map((m) => m.id));
    if (!j.nextPageToken) break;
    pageToken = j.nextPageToken;
  }
  ids = ids.slice(0, max);
  const hdr = ["From", "To", "Cc"].map((h) => `metadataHeaders=${h}`).join("&");
  for (let i = 0; i < ids.length; i += 20) {
    await Promise.all(ids.slice(i, i + 20).map(async (id) => {
      try {
        const m = await gapi(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=metadata&${hdr}`);
        for (const h of m.payload?.headers || []) {
          for (const part of h.value.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)) {
            const mm = part.match(/^\s*"?([^"<]+?)"?\s*<([^>]+@umich\.edu)>/i);
            if (!mm) continue;
            const email = mm[2].toLowerCase();
            seen[email] = { name: mm[1].trim(), count: (seen[email]?.count || 0) + 1 };
          }
        }
      } catch {}
    }));
  }
  const people = Object.entries(seen).map(([email, v]) => ({ email, ...v }));
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(GMAIL_CACHE, JSON.stringify({ scannedAt: new Date().toISOString(), messages: ids.length, people }, null, 2));
  chmodSync(GMAIL_CACHE, 0o600);
  return { messages: ids.length, people: people.length };
}

// ---------- Calendar: learn friends' UMich emails from people on your past events ----------
// Uses the attendee lists of the last year of events on your calendar (no new permission needed).
// Attendees shown only by email get their name from the UMich directory.
const CAL_CACHE = join(DATA_DIR, "calendar-people.json");
export async function scanCalendar() {
  const now = new Date();
  const seen = {};
  let pageToken = "", events = 0, me = null;
  do {
    const q = new URLSearchParams({ timeMin: new Date(now.getTime() - 365 * 86400000).toISOString(), timeMax: now.toISOString(),
      singleEvents: "true", maxResults: "2500", ...(pageToken ? { pageToken } : {}) });
    const j = await gapi(`https://www.googleapis.com/calendar/v3/calendars/primary/events?${q}`);
    for (const ev of j.items || []) {
      events++;
      for (const a of ev.attendees || []) {
        if (a.self) { me = a.email; continue; }
        if (!/@umich\.edu$/i.test(a.email || "") || a.resource) continue;
        const email = a.email.toLowerCase();
        seen[email] = { name: a.displayName || seen[email]?.name || "", count: (seen[email]?.count || 0) + 1 };
      }
    }
    pageToken = j.nextPageToken || "";
  } while (pageToken);
  // Fill in names for attendees listed by email only.
  for (const [email, v] of Object.entries(seen)) {
    if (v.name) continue;
    try {
      const q = new URLSearchParams({ query: email, readMask: "names", sources: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE", pageSize: "1" });
      const j = await gapi(`https://people.googleapis.com/v1/people:searchDirectoryPeople?${q}`);
      v.name = j.people?.[0]?.names?.[0]?.displayName || "";
    } catch {}
  }
  const people = Object.entries(seen).filter(([e]) => e !== me).map(([email, v]) => ({ email, ...v })).filter((p) => p.name);
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(CAL_CACHE, JSON.stringify({ scannedAt: now.toISOString(), events, people }, null, 2));
  chmodSync(CAL_CACHE, 0o600);
  return { events, people: people.length };
}

/// Match a contact name ("LILYY", "Natalie (math)", "Owen") to someone you've emailed at umich.edu.
/// Picks the person you've emailed most among those whose first name matches; null if none.
export function emailFromGmail(contactName) {
  // Your corrections: "Sam" → "Samantha Lee" (data/reach-overrides.json).
  let aliases = {};
  try { aliases = JSON.parse(readFileSync(join(DATA_DIR, "reach-overrides.json"), "utf8")).aliases || {}; } catch {}
  const want = norm(aliases[contactName] || contactName).split(" ");
  for (const file of [CAL_CACHE, GMAIL_CACHE]) {
    let data;
    try { data = JSON.parse(readFileSync(file, "utf8")); } catch { continue; }
    const hit = bestMatch(data.people, want);
    if (hit) return hit;
  }
  return null;
}

// Common nicknames → full first names (plus any prefix like Kat → Katherine).
const NICK = {
  lily: ["lillian", "liliana", "lilian"], nate: ["nathan", "nathaniel"], gwyn: ["gwyneth", "gwendolyn"],
  maya: ["mayaa", "maia"], kate: ["katherine", "kathryn", "catherine"], katie: ["katherine", "kathryn"],
  alex: ["alexander", "alexandra", "alexis"], sam: ["samuel", "samantha"], chris: ["christopher", "christina", "christine"],
  matt: ["matthew"], mike: ["michael"], nick: ["nicholas"], will: ["william"], ben: ["benjamin"], dan: ["daniel"],
  jen: ["jennifer"], liz: ["elizabeth"], beth: ["elizabeth"], abby: ["abigail"], maddie: ["madeline", "madison"],
};
const sameFirst = (contact, real) =>
  contact === real || real.startsWith(contact) || (NICK[contact] || []).includes(real);

function bestMatch(people, want) {
  const hits = people.filter((p) => {
    const have = norm(p.name).split(" ");
    if (!sameFirst(want[0], have[0])) return false;
    return want.length < 2 || have.includes(want[1]);   // if the contact has a last name, it must match too
  });
  hits.sort((a, b) => b.count - a.count);
  return hits[0] || null;
}

// ---------- directory: guess a friend's UMich email from their name ----------
function loadCache() { try { return JSON.parse(readFileSync(DIR_CACHE, "utf8")); } catch { return {}; } }
export async function guessEmail(fullName) {
  const fromMail = emailFromGmail(fullName);       // best source: people you actually email
  if (fromMail) return fromMail.email;
  const cache = loadCache();
  if (cache[fullName]) return cache[fullName];
  const parts = fullName.trim().split(/\s+/);
  let email = null;
  if (parts.length >= 2) {   // a first name alone ("Owen") matches too many people to guess
    const q = new URLSearchParams({ query: fullName, readMask: "names,emailAddresses", sources: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE", pageSize: "5" });
    const j = await gapi(`https://people.googleapis.com/v1/people:searchDirectoryPeople?${q}`);
    const hits = (j.people || []).filter((p) => (p.names?.[0]?.displayName || "").toLowerCase() === fullName.toLowerCase());
    if (hits.length === 1) email = hits[0].emailAddresses?.[0]?.value || null;   // only when it's unambiguous
  }
  cache[fullName] = email;
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(DIR_CACHE, JSON.stringify(cache, null, 2));
  return email;
}

// ---------- free/busy: the first evening hour you're both free this week ----------
const overlaps = (a0, a1, busy) => busy.some((b) => a0 < new Date(b.end) && a1 > new Date(b.start));
export async function findSlot(friendEmail, fromDay = 0) {
  const now = new Date();
  const end = new Date(now.getTime() + 7 * 86400000);
  const items = [{ id: "primary" }, ...(friendEmail ? [{ id: friendEmail }] : [])];
  const fb = await gapi("https://www.googleapis.com/calendar/v3/freeBusy", { method: "POST", body: { timeMin: now.toISOString(), timeMax: end.toISOString(), items } });
  const mine = fb.calendars?.primary?.busy || [];
  const theirsCal = friendEmail ? fb.calendars?.[friendEmail] : null;
  const canSeeThem = !!theirsCal && !theirsCal.errors?.length;
  const theirs = canSeeThem ? theirsCal.busy || [] : [];
  // Start looking on `fromDay` (0 = today) so a deck of people spreads across the week, then wrap around.
  for (let i = 0; i < 7; i++) {
    const d = (fromDay + i) % 7;
    for (const hour of [19, 18, 20]) {   // dinner-time first
      const s = new Date(now); s.setDate(now.getDate() + d); s.setHours(hour, 0, 0, 0);
      const e = new Date(s.getTime() + 3600000);
      if (s.getTime() < now.getTime() + 2 * 3600000) continue;
      if (!overlaps(s, e, mine) && !overlaps(s, e, theirs)) {
        // That evening's busy times (yours and theirs, no details) for the card's day view.
        const d0 = new Date(s); d0.setHours(16, 0, 0, 0);
        const d1 = new Date(s); d1.setHours(23, 0, 0, 0);
        const clip = (b) => ({ start: new Date(Math.max(new Date(b.start), d0)).toISOString(), end: new Date(Math.min(new Date(b.end), d1)).toISOString() });
        const inDay = (b) => new Date(b.start) < d1 && new Date(b.end) > d0;
        return { start: s.toISOString(), end: e.toISOString(), bothFree: canSeeThem,
                 busy: { mine: mine.filter(inDay).map(clip), theirs: theirs.filter(inDay).map(clip) } };
      }
    }
  }
  return null;
}

// ---------- create the plan on your calendar ----------
export async function createPlan({ title, start, end, friendEmail, location }) {
  const attendees = SEND_INVITES && friendEmail ? [{ email: friendEmail }] : undefined;
  const q = new URLSearchParams({ sendUpdates: SEND_INVITES ? "all" : "none" });
  return gapi(`https://www.googleapis.com/calendar/v3/calendars/primary/events?${q}`, {
    method: "POST",
    body: { summary: title, location: location || undefined, start: { dateTime: start }, end: { dateTime: end }, attendees,
            description: "Planned with Loose Ends" },
  });
}
