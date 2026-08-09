#!/usr/bin/env node
// fetch-vendor-sources.mjs — DEV-ONLY: resolve vendor sets -> selling NPC(s) +
// coordinates + piece costs, from Wowhead's public pages (no client API exists
// for any of this).
//
// Default run, two sequential phases (both resumable, caches per ID):
//   1. sets  : one representative piece per vendor-dominant set -> the item
//              page's "sold by" listview (npcID, name, faction reacts, zone,
//              cost). If a set's first piece isn't sold anymore, the next
//              pieces are tried (up to 3 per set).
//   2. npcs  : every npc discovered in phase 1 -> its page's g_mapperData
//              (Wowhead zone id + 0-100 coords, same projection as the
//              in-game maps). Zone with the most sightings wins; coords are
//              the centroid of its cluster.
//
// --costs : opt-in third phase — EVERY piece of every vendor-dominant set
//           (7k+ items, hours of throttled fetching; run overnight, it
//           resumes where it stopped). Fills the per-piece cost table that
//           build-sets.mjs bakes for set-total price display.
//
// Reads  : data/sets-export.lua
// Writes : data/vendor-sources.json { itemID: [rows] } ([] = fetched, unsold)
//          data/npc-locations.json  { npcID: { name, zone, x, y } | {} }
// Wowhead zone ids are AreaTable ids, NOT uiMapIDs: build-sets.mjs translates
// them through data/zone-uimap.json (hand-authored) and warns on gaps.
// Usage  : node scripts/fetch-vendor-sources.mjs [--costs]

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import luaparse from 'luaparse';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const SRC = join(ROOT, 'data', 'sets-export.lua');
const OUT_ITEMS = join(ROOT, 'data', 'vendor-sources.json');
const OUT_NPCS = join(ROOT, 'data', 'npc-locations.json');

const COSTS = process.argv.includes('--costs');
const THROTTLE_MS = 1200;         // gentle: CloudFront hard-blocks bursty clients
const MAX_CONSECUTIVE_FAILS = 10; // sustained 403s = we're blocked, stop cleanly
const MAX_PIECES_PER_SET = 3;     // discovery fallbacks when a piece isn't sold
const MAX_ROWS_PER_ITEM = 6;      // replica gear is sold by many twin vendors
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

// --- vendor-dominant sets and their piece lists -----------------------------------
const gen = readGen();
const sets = Array.isArray(gen.sets) ? gen.sets : Object.values(gen.sets || {});
const vendorSets = [];
for (const rec of sets) {
  const pieces = Array.isArray(rec.pieces) ? rec.pieces : Object.values(rec.pieces || {});
  const items = pieces.filter((p) => p.st === 3 && p.itemID != null).map((p) => p.itemID);
  if (items.length > 0 && items.length > pieces.length / 2) {
    vendorSets.push({ setID: rec.setID, items });
  }
}

const itemCache = existsSync(OUT_ITEMS) ? JSON.parse(readFileSync(OUT_ITEMS, 'utf8')) : {};
const npcCache = existsSync(OUT_NPCS) ? JSON.parse(readFileSync(OUT_NPCS, 'utf8')) : {};
const flush = () => {
  writeFileSync(OUT_ITEMS, JSON.stringify(itemCache, null, 0));
  writeFileSync(OUT_NPCS, JSON.stringify(npcCache, null, 0));
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- shared fetch/parse helpers ----------------------------------------------------
// returns the page body, or undefined on transient failure (never cache those)
async function fetchPage(url) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      if (res.status === 429 || res.status === 403) { await sleep(5000 * attempt); continue; }
      if (!res.ok) return undefined;
      return await res.text();
    } catch {
      await sleep(2000 * attempt);
    }
  }
  return undefined;
}

// a Listview's data rows are plain JSON on a single line
function parseListview(body, id) {
  const at = body.indexOf(`id: '${id}'`);
  if (at < 0) return [];
  const m = body.slice(at, at + 900000).match(/data: (\[.*\]),?\s*\n?\}\)/);
  if (!m) return [];
  try { return JSON.parse(m[1]); } catch { return []; }
}

// trim a sold-by row to what the build needs
function trimRow(r) {
  return {
    id: r.id, name: r.name, react: r.react || null,
    zone: Array.isArray(r.location) ? r.location[0] : null,
    cost: r.cost || null, pop: r.popularity || 0,
  };
}

// fetch one item's sold-by rows; undefined on transient failure
async function fetchSoldBy(itemID) {
  const body = await fetchPage(`https://www.wowhead.com/item=${itemID}`);
  if (body === undefined) return undefined;
  const rows = parseListview(body, 'sold-by').map(trimRow);
  rows.sort((a, b) => b.pop - a.pop);
  return rows.slice(0, MAX_ROWS_PER_ITEM);
}

let consecutiveFails = 0;
function noteFailure() {
  if (++consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
    console.log(`\n${consecutiveFails} consecutive failures — Wowhead is blocking this IP.`);
    console.log('Progress is saved; re-run the script in a few hours, it resumes where it stopped.');
    flush();
    process.exit(1);
  }
}

// --- phase 1: one sold-by lookup per set (with fallback pieces) --------------------
async function phaseSets() {
  const pending = vendorSets.filter((s) => !s.items.slice(0, MAX_PIECES_PER_SET)
    .some((i) => Array.isArray(itemCache[i]) && itemCache[i].length));
  console.log(`phase sets: ${vendorSets.length} vendor sets, ${pending.length} without a resolved vendor yet`);
  let done = 0, found = 0;
  for (const s of pending) {
    for (const itemID of s.items.slice(0, MAX_PIECES_PER_SET)) {
      if (itemID in itemCache) { if (itemCache[itemID].length) break; else continue; }
      const rows = await fetchSoldBy(itemID);
      await sleep(THROTTLE_MS);
      if (rows === undefined) { noteFailure(); continue; }
      consecutiveFails = 0;
      itemCache[itemID] = rows;
      if (rows.length) { found++; break; }
    }
    done++;
    if (done % 25 === 0 || done === pending.length) {
      flush();
      console.log(`… ${done}/${pending.length} sets probed, ${found} vendors found this run`);
    }
  }
  flush();
}

// --- phase 2: coordinates for every discovered npc ---------------------------------
function parseMapper(body) {
  const at = body.indexOf('g_mapperData = ');
  if (at < 0) return null;
  const end = body.indexOf(';\n', at);
  if (end < 0) return null;
  try { return JSON.parse(body.slice(at + 'g_mapperData = '.length, end)); } catch { return null; }
}

async function phaseNpcs() {
  const wanted = new Map(); // npcID -> name (from sold-by rows)
  for (const rows of Object.values(itemCache)) {
    for (const r of rows) if (!(r.id in npcCache)) wanted.set(r.id, r.name);
  }
  console.log(`phase npcs: ${wanted.size} npcs to locate`);
  let done = 0, located = 0;
  for (const [npcID, name] of wanted) {
    const body = await fetchPage(`https://www.wowhead.com/npc=${npcID}`);
    await sleep(THROTTLE_MS);
    if (body === undefined) { noteFailure(); continue; }
    consecutiveFails = 0;
    const mapper = parseMapper(body);
    if (!mapper) { npcCache[npcID] = { name }; done++; continue; } // no coords (instance/cave)
    // zone with the most sightings; centroid of all its coords
    let best = null;
    for (const [zone, groups] of Object.entries(mapper)) {
      const coords = groups.flatMap((g) => g.coords || []);
      if (!coords.length) continue;
      if (!best || coords.length > best.coords.length) best = { zone: Number(zone), coords };
    }
    if (best) {
      const cx = best.coords.reduce((a, c) => a + c[0], 0) / best.coords.length;
      const cy = best.coords.reduce((a, c) => a + c[1], 0) / best.coords.length;
      npcCache[npcID] = { name, zone: best.zone, x: Math.round(cx * 10) / 10, y: Math.round(cy * 10) / 10 };
      located++;
    } else {
      npcCache[npcID] = { name };
    }
    done++;
    if (done % 25 === 0 || done === wanted.size) {
      flush();
      console.log(`… ${done}/${wanted.size} npcs fetched, ${located} located this run`);
    }
  }
  flush();
}

// --- phase 3 (--costs): every piece of every vendor set ----------------------------
async function phaseCosts() {
  const targets = new Set();
  for (const s of vendorSets) for (const i of s.items) if (!(i in itemCache)) targets.add(i);
  console.log(`phase costs: ${targets.size} pieces still to fetch (of ${vendorSets.reduce((a, s) => a + s.items.length, 0)})`);
  let done = 0;
  for (const itemID of targets) {
    const rows = await fetchSoldBy(itemID);
    await sleep(THROTTLE_MS);
    if (rows === undefined) { noteFailure(); continue; }
    consecutiveFails = 0;
    itemCache[itemID] = rows;
    done++;
    if (done % 25 === 0 || done === targets.size) {
      flush();
      console.log(`… ${done}/${targets.size} pieces fetched`);
    }
  }
  flush();
}

if (COSTS) {
  await phaseCosts();
} else {
  await phaseSets();
  await phaseNpcs();
}

const soldItems = Object.values(itemCache).filter((r) => r.length).length;
const locatedNpcs = Object.values(npcCache).filter((n) => n.zone).length;
console.log(`done: ${soldItems} sold items cached, ${Object.keys(npcCache).length} npcs (${locatedNpcs} located).`);
