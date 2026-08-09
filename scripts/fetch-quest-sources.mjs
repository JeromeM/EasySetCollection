#!/usr/bin/env node
// fetch-quest-sources.mjs — DEV-ONLY one-off: resolve item -> questID for the
// quest pieces the in-game scan couldn't match (the server only serves reward
// data for recent/world quests, so /esc genquests caps out on old content).
//
// Default (XML) pass — Wowhead's public item XML feed. For quest-reward items
// the <json> blob carries `"source":[4]` and a sourcemore entry
// `{"t":5,"ti":<questID>}`. Only t=5 (quest) entries are taken, so items the
// client mislabels as quest rewards simply stay unmatched instead of getting
// a wrong ID.
//
// --deep (HTML) pass — for the XML pass's definitive misses (cached null):
// fetches the full item page, whose "Reward from" quest listview knows quests
// the XML sourcemore omits (old content, multi-quest rewards). Rows prefer
// side=3 (both factions), then popularity. Every deep-fetched item is
// recorded in data/item-sources.json (so reruns skip it); quest rows land
// there too. NOTE: the item's OWN source/sourcemore is NOT in the HTML page
// (tooltips load via XHR) — for classification data (crafted t=6, boss drop
// t=1, world drop) re-fetch the misses' XML and read the full sourcemore.
//
// Reads  : data/sets-export.lua   (quest pieces + in-game questRewards)
//          data/quest-sources.json (previous runs — resumable, misses cached)
//          data/item-sources.json  (--deep marker + source captures)
// Writes : data/quest-sources.json { itemID: questID | null }
//          data/item-sources.json  { itemID: { quests, source, sm } }
// Usage  : node scripts/fetch-quest-sources.mjs [--deep]   (throttled ~1 req/s)
//
// build-sets.mjs merges quest-sources.json with the in-game questRewards
// (in-game wins).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import luaparse from 'luaparse';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const SRC = join(ROOT, 'data', 'sets-export.lua');
const OUT = join(ROOT, 'data', 'quest-sources.json');
const OUT_DEEP = join(ROOT, 'data', 'item-sources.json');

const DEEP = process.argv.includes('--deep');
const THROTTLE_MS = DEEP ? 1200 : 1000; // gentle: CloudFront hard-blocks bursty clients
const MAX_CONSECUTIVE_FAILS = 10; // sustained 403s = we're blocked, stop cleanly
const UA = 'Mozilla/5.0 (EasySetCollection build tooling; one-off dev import)';

// --- evaluate a luaparse table-literal AST into a plain JS value ---------------
function evalNode(node) {
  switch (node.type) {
    case 'StringLiteral':
      return node.value != null ? node.value : node.raw.slice(1, -1);
    case 'NumericLiteral':
      return node.value;
    case 'BooleanLiteral':
      return node.value;
    case 'NilLiteral':
      return null;
    case 'UnaryExpression':
      return node.operator === '-' ? -evalNode(node.argument) : evalNode(node.argument);
    case 'TableConstructorExpression': {
      const arrayOnly = node.fields.every((f) => f.type === 'TableValue');
      if (arrayOnly) return node.fields.map((f) => evalNode(f.value));
      const obj = {};
      for (const f of node.fields) {
        if (f.type === 'TableKeyString') obj[f.key.name] = evalNode(f.value);
        else if (f.type === 'TableKey') obj[evalNode(f.key)] = evalNode(f.value);
        else obj[obj.__n = (obj.__n || 0) + 1] = evalNode(f.value);
      }
      delete obj.__n;
      return obj;
    }
    default:
      throw new Error('unhandled node: ' + node.type);
  }
}

function readGen() {
  const ast = luaparse.parse(readFileSync(SRC, 'utf8'), { luaVersion: '5.1' });
  for (const stmt of ast.body) {
    if (stmt.type === 'AssignmentStatement'
        && stmt.variables[0]?.type === 'Identifier'
        && stmt.variables[0].name === 'EasySetCollectionGen') {
      return evalNode(stmt.init[0]);
    }
  }
  throw new Error('EasySetCollectionGen not found in ' + SRC);
}

// --- collect the itemIDs still needing a questID ---------------------------------
const gen = readGen();
const sets = Array.isArray(gen.sets) ? gen.sets : Object.values(gen.sets || {});
const ingame = gen.questRewards || {};
const known = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
const deepKnown = existsSync(OUT_DEEP) ? JSON.parse(readFileSync(OUT_DEEP, 'utf8')) : {};

const targets = new Set();
for (const rec of sets) {
  const pieces = Array.isArray(rec.pieces) ? rec.pieces : Object.values(rec.pieces || {});
  for (const p of pieces) {
    if (p.st !== 2 || p.itemID == null) continue;
    if (ingame[p.itemID] != null) continue;    // the in-game scan already has it
    if (DEEP) {
      // deep pass: only the XML pass's definitive misses, not yet deep-fetched
      if (known[p.itemID] === null && !(p.itemID in deepKnown)) targets.add(p.itemID);
    } else if (!(p.itemID in known)) {         // fetched previously (hit or miss)
      targets.add(p.itemID);
    }
  }
}

console.log(`quest pieces to resolve via Wowhead${DEEP ? ' (deep HTML pass)' : ''}: ${targets.size}`
  + ` (in-game matched: ${Object.keys(ingame).length},`
  + ` cached from previous runs: ${Object.keys(known).length})`);

// --- fetch -----------------------------------------------------------------------
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// returns a questID, null (definitive miss), or undefined (transient failure —
// blocked/HTTP error: must NOT be cached as a miss)
async function fetchQuestID(itemID) {
  const url = `https://www.wowhead.com/item=${itemID}&xml`;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.status === 429 || res.status === 403) { await sleep(5000 * attempt); continue; }
      if (!res.ok) return undefined;
      const body = await res.text();
      const sm = body.match(/"sourcemore":\[(.*?)\]/);
      if (!sm) return null;
      // take the first quest-typed (t=5) source entry
      for (const entry of sm[1].matchAll(/\{[^}]*\}/g)) {
        const e = entry[0];
        if (/"t":5\b/.test(e)) {
          const ti = e.match(/"ti":(\d+)/);
          if (ti) return Number(ti[1]);
        }
      }
      return null;
    } catch {
      await sleep(2000 * attempt);
    }
  }
  return undefined;
}

// --- deep pass: full item page -----------------------------------------------------
// The "Reward from" listview rows are plain JSON on a single line:
//   new Listview({ template: 'quest', id: 'reward-from-q', …, data: [{...}], });
function parseRewardFrom(body) {
  const at = body.indexOf("id: 'reward-from-q'");
  if (at < 0) return [];
  const m = body.slice(at, at + 300000).match(/data: (\[.*\]),?\s*\n?\}\)/);
  if (!m) return [];
  try { return JSON.parse(m[1]); } catch { return []; }
}

// The item's own json blob (keyed by id in the page data) — best-effort capture
// of source/sourcemore for later classification fixes.
function parseOwnSource(body, itemID) {
  const key = '"' + itemID + '":{';
  let at = body.indexOf(key);
  while (at >= 0) {
    const chunk = body.slice(at, at + 4000);
    if (chunk.includes('"source"')) {
      const out = {};
      const src = chunk.match(/"source":\[([\d,]*)\]/);
      if (src) out.source = src[1] ? src[1].split(',').map(Number) : [];
      const sm = chunk.match(/"sourcemore":\[(.*?)\](?=[,}])/);
      if (sm) { try { out.sm = JSON.parse('[' + sm[1] + ']'); } catch { /* keep without */ } }
      if (out.source || out.sm) return out;
    }
    at = body.indexOf(key, at + 1);
  }
  return {};
}

// returns { questID, meta }, or undefined on transient failure (must not cache)
async function fetchDeep(itemID) {
  const url = `https://www.wowhead.com/item=${itemID}`;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.status === 429 || res.status === 403) { await sleep(5000 * attempt); continue; }
      if (!res.ok) return undefined;
      const body = await res.text();
      const rows = parseRewardFrom(body);
      // both-factions quests first, then the most popular row
      rows.sort((a, b) => ((b.side === 3) - (a.side === 3)) || ((b.popularity || 0) - (a.popularity || 0)));
      const meta = parseOwnSource(body, itemID);
      if (rows.length) meta.quests = rows.map((r) => ({ id: r.id, side: r.side }));
      return { questID: rows.length ? rows[0].id : null, meta };
    } catch {
      await sleep(2000 * attempt);
    }
  }
  return undefined;
}

function flush() {
  writeFileSync(OUT, JSON.stringify(known, null, 0));
  if (DEEP) writeFileSync(OUT_DEEP, JSON.stringify(deepKnown, null, 0));
}

let done = 0, found = 0, consecutiveFails = 0;
for (const itemID of targets) {
  let questID;
  if (DEEP) {
    const r = await fetchDeep(itemID);
    if (r !== undefined) {
      deepKnown[itemID] = r.meta;             // marks the item as deep-fetched
      if (r.questID) known[itemID] = r.questID;
    }
    questID = r === undefined ? undefined : r.questID;
  } else {
    questID = await fetchQuestID(itemID);
  }
  done++;
  if (questID === undefined) {
    consecutiveFails++;
    if (consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
      console.log(`\n${consecutiveFails} consecutive failures — Wowhead is blocking this IP.`);
      console.log('Progress is saved; re-run the script in a few hours, it resumes where it stopped.');
      break;
    }
  } else {
    consecutiveFails = 0;
    if (!DEEP) known[itemID] = questID;   // null too: caches the definitive miss
    if (questID) found++;
  }
  if (done % 25 === 0 || done === targets.size) {
    flush();
    console.log(`… ${done}/${targets.size} fetched, ${found} quest matches this run`);
  }
  await sleep(THROTTLE_MS);
}
flush();

const totalKnown = Object.values(known).filter((v) => v != null).length;
console.log(`done: ${found} new matches this run; quest-sources.json now maps ${totalKnown} items.`);
