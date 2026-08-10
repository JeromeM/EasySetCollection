#!/usr/bin/env node
// fetch-token-sources.mjs — DEV-ONLY: resolve the TIER TOKEN chain.
//
// Tier pieces are not bought, they are exchanged: the vendor takes a token
// ("Helm of the Fallen Champion") that a raid boss drops. Saying "Vendor:
// Arodis Sunblade" is technically true and useless — what you must farm is
// Prince Malchezaar in Karazhan. This resolves, for every token a vendor set
// asks for, which NPC drops it.
//
// Reads  : data/vendor-sources.json (the cost of each priced piece)
// Writes : data/token-sources.json  { tokenItemID: { name, drops: [npcID] } }
//          ({} for ids that drop from nobody — currencies, honor, marks)
// Usage  : node scripts/fetch-token-sources.mjs   (~1 fetch/s, resumable)

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const SRC = join(ROOT, 'data', 'vendor-sources.json');
const OUT = join(ROOT, 'data', 'token-sources.json');

const THROTTLE_MS = 1200;
const MAX_CONSECUTIVE_FAILS = 10;
const MAX_DROPS = 4;
const UA = 'Mozilla/5.0 (EasySetCollection build tooling; one-off dev import)';

// --- which ids are used as payment ----------------------------------------------------
const vendCache = JSON.parse(readFileSync(SRC, 'utf8'));
const wanted = new Set();
for (const rows of Object.values(vendCache)) {
  if (!Array.isArray(rows) || !rows.length) continue;
  const cost = rows[0].cost && rows[0].cost[0];
  if (!Array.isArray(cost)) continue;
  // Wowhead files token ITEMS in both the item slot and the currency slot
  for (const pair of [...(cost[1] || []), ...(cost[2] || [])]) {
    if (Array.isArray(pair) && pair[0]) wanted.add(pair[0]);
  }
}

const out = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
const todo = [...wanted].filter((id) => !(id in out));
console.log(`payment ids: ${wanted.size} (${todo.length} left to resolve)`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchPage(url) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.status === 429 || res.status === 403) { await sleep(5000 * attempt); continue; }
      if (!res.ok) return null;   // 404: a currency id, not an item
      return await res.text();
    } catch {
      await sleep(2000 * attempt);
    }
  }
  return undefined;
}

// the "Dropped by" listview holds npc rows: id, name, and the drop chance
function parseDroppedBy(body) {
  const at = body.indexOf("id: 'dropped-by'");
  if (at < 0) return [];
  const m = body.slice(at, at + 600000).match(/data: (\[.*\]),?\s*\n?\}\)/);
  if (!m) return [];
  try {
    const rows = JSON.parse(m[1]);
    rows.sort((a, b) => (b.percent || 0) - (a.percent || 0));
    return rows.slice(0, MAX_DROPS).map((r) => ({ npc: r.id, name: r.name }));
  } catch {
    return [];
  }
}

let done = 0, found = 0, fails = 0;
for (const id of todo) {
  const body = await fetchPage(`https://www.wowhead.com/item=${id}`);
  await sleep(THROTTLE_MS);
  done++;
  if (body === undefined) {
    if (++fails >= MAX_CONSECUTIVE_FAILS) {
      console.log('\nblocked by Wowhead — progress saved, rerun later');
      break;
    }
    continue;
  }
  fails = 0;
  if (body === null) { out[id] = {}; continue; }   // not an item page
  const name = (body.match(/g_pageInfo = \{"type":\d+,"typeId":\d+,"name":"((?:[^"\\]|\\.)*)"/) || [])[1];
  const drops = parseDroppedBy(body);
  out[id] = drops.length ? { name: name ? JSON.parse('"' + name + '"') : null, drops } : {};
  if (drops.length) found++;
  if (done % 25 === 0 || done === todo.length) {
    writeFileSync(OUT, JSON.stringify(out, null, 0));
    console.log(`… ${done}/${todo.length}, ${found} with a boss drop`);
  }
}
writeFileSync(OUT, JSON.stringify(out, null, 0));
const withDrops = Object.values(out).filter((v) => v.drops && v.drops.length).length;
console.log(`done: ${withDrops}/${Object.keys(out).length} payment items drop from a boss.`);
