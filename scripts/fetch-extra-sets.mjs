#!/usr/bin/env node
// fetch-extra-sets.mjs — DEV-ONLY: harvest Wowhead's transmog-set database for
// the sets the in-game journal does NOT have (dungeon recolors, world sets,
// old PvP off-sets, event gear — the Better-Wardrobe territory).
//
// Three phases, all incremental (reruns only fetch what's new):
//   1. sitemap  : /sitemap/transmog-set — the COMPLETE id universe (1 fetch).
//   2. sweep    : the index page embeds full rows inline (`var transmogSets`):
//                 id, name, piece itemIDs, armor type, class mask, quality and
//                 a `_note` subcategory id. One fetch per expansion (facet 3,
//                 syntax `?filter=3;<opt>;`), capped at 500 rows server-side —
//                 capped pages get a recolor sub-split (`?filter=3:2;<e>:<r>;;`).
//   3. backfill : sitemap ids the sweeps never returned (capped tails, new
//                 sets) — the individual page carries the name (g_pageInfo)
//                 and the itemIDs (a clean JSON script tag). Backfilled sets
//                 have no armor/class/category metadata: the runtime derives
//                 those from the items themselves.
//
// Journal sets also live in the index: any set sharing half its itemIDs with
// a journal set (data/sets-export.lua) is dropped as a duplicate — backfilled
// dupes are remembered so their pages are never fetched twice.
//
// NOTE: Wowhead transmog-set names are community-authored English names (the
// game has none for these sets) — no locale variants exist to fetch.
//
// Reads  : data/sets-export.lua   (journal itemIDs for the dedupe)
// Writes : data/extra-sets.json   { sets: { id: { name, exp, at, rc, q, cat,
//                                  src, pieces } }, dupes: { id: true } }
// Usage  : node scripts/fetch-extra-sets.mjs
//          (~15 fetches once primed; the first run backfills a few hundred
//           individual pages, throttled ~1/s, resumable)
//
// Weekly automation (planned): a scheduled workflow reruns this from main;
// pure additions auto-release as X.Y.Z.<n> data bumps.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import luaparse from 'luaparse';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const SRC = join(ROOT, 'data', 'sets-export.lua');
const OUT = join(ROOT, 'data', 'extra-sets.json');

const THROTTLE_MS = 1200;
const MAX_CONSECUTIVE_FAILS = 10;
const UA = 'Mozilla/5.0 (EasySetCollection build tooling; one-off dev import)';
const EXPANSIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]; // facet-3 option ids (1 = Classic … 12 = Midnight)
const OVERLAP_DUPLICATE = 0.5;   // half the pieces in one journal set = same set

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

// --- journal item index (for the duplicate check) -----------------------------------
const gen = readGen();
const journalSets = Array.isArray(gen.sets) ? gen.sets : Object.values(gen.sets || {});
const itemToJournal = new Map();   // itemID -> [journal setID, ...]
for (const rec of journalSets) {
  const pieces = Array.isArray(rec.pieces) ? rec.pieces : Object.values(rec.pieces || {});
  for (const p of pieces) {
    if (p.itemID != null) {
      const list = itemToJournal.get(p.itemID) || [];
      list.push(rec.setID);
      itemToJournal.set(p.itemID, list);
    }
  }
}

function journalDuplicate(pieces) {
  if (!pieces.length) return true;   // nothing to collect -> useless anyway
  const perSet = new Map();
  for (const itemID of pieces) {
    for (const sid of itemToJournal.get(itemID) || []) {
      perSet.set(sid, (perSet.get(sid) || 0) + 1);
    }
  }
  for (const n of perSet.values()) {
    if (n / pieces.length >= OVERLAP_DUPLICATE) return true;
  }
  return false;
}

// --- state --------------------------------------------------------------------------
const state = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
const sets = state.sets || {};
const dupes = state.dupes || {};
const flush = () => writeFileSync(OUT, JSON.stringify({ sets, dupes }, null, 0));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let consecutiveFails = 0;
function noteFailure(what) {
  if (++consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
    console.log(`\n${consecutiveFails} consecutive failures (${what}) — Wowhead is blocking this IP.`);
    console.log('Progress is saved; re-run in a few hours, it resumes where it stopped.');
    flush();
    process.exit(1);
  }
}

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

// --- phase 1: the complete id universe ------------------------------------------------
const smBody = await fetchPage('https://www.wowhead.com/sitemap/transmog-set?page=1');
if (smBody === undefined) { console.log('sitemap fetch failed, aborting'); process.exit(1); }
const universe = [...new Set([...smBody.matchAll(/transmog-set=(\d+)/g)].map((m) => Number(m[1])))];
console.log(`sitemap: ${universe.length} transmog-set ids`);
await sleep(THROTTLE_MS);

// --- phase 2: index sweeps -------------------------------------------------------------
const seen = new Set();   // ids returned by any sweep this run (incl. journal dupes)

function takeRow(r, exp) {
  seen.add(r.id);
  if (!Array.isArray(r.pieces)) return;
  if (journalDuplicate(r.pieces)) { dupes[r.id] = true; delete sets[r.id]; return; }
  sets[r.id] = {
    name: r.name, exp,
    at: r.armorType ?? null,          // armor type
    rc: r.reqclass || null,           // class bitmask (0/absent = anyone)
    q: r.quality ?? null,
    cat: r._note || null,             // subcategory id (Tier 2 Raid Set, Dungeon Set 1, …)
    src: r.source ?? null,
    pieces: r.pieces,
  };
}

async function sweep(filter, exp, label) {
  const body = await fetchPage(`https://www.wowhead.com/transmog-sets?filter=${filter}`);
  await sleep(THROTTLE_MS);
  if (body === undefined) { console.log(`WARN sweep ${label}: fetch failed`); noteFailure('sweep'); return null; }
  consecutiveFails = 0;
  const at = body.indexOf('var transmogSets');
  const m = at >= 0 && body.slice(at).match(/var transmogSets\s*=\s*(\[.*?\]);\n/);
  const rows = m ? JSON.parse(m[1]) : [];
  for (const r of rows) takeRow(r, exp);
  console.log(`sweep ${label}: ${rows.length} rows${rows.length >= 500 ? ' (CAPPED)' : ''}`);
  return rows.length;
}

for (const exp of EXPANSIONS) {
  const n = await sweep(`3;${exp};`, exp, `expansion ${exp}`);
  if (n !== null && n >= 500) {
    // capped: recolor sub-split recovers part of the truncated tail
    await sweep(`3:2;${exp}:1;;`, exp, `expansion ${exp} recolors`);
    await sweep(`3:2;${exp}:2;;`, exp, `expansion ${exp} non-recolors`);
  }
}

// --- phase 3: backfill the ids no sweep returned ---------------------------------------
const missing = universe.filter((id) => !seen.has(id) && !sets[id] && !dupes[id]);
console.log(`backfill: ${missing.length} ids missing from the sweeps`);

let done = 0, added = 0;
for (const id of missing) {
  const body = await fetchPage(`https://www.wowhead.com/transmog-set=${id}`);
  await sleep(THROTTLE_MS);
  done++;
  if (body === undefined) { noteFailure('backfill'); continue; }
  consecutiveFails = 0;
  const name = (body.match(/g_pageInfo = \{"type":\d+,"typeId":\d+,"name":"((?:[^"\\]|\\.)*)"/) || [])[1];
  const itemsJson = (body.match(/id="data\.transmog-set-detail-page-items">(\[[^\]]*\])/) || [])[1];
  let pieces = [];
  try { pieces = itemsJson ? JSON.parse(itemsJson) : []; } catch { /* leave empty */ }
  if (!name || !pieces.length || journalDuplicate(pieces)) {
    dupes[id] = true;   // dead page, empty or journal set: never refetch
  } else {
    // no index row: armor/class/category derive from the items at runtime
    sets[id] = { name: JSON.parse('"' + name + '"'), exp: null, at: null, rc: null,
                 q: null, cat: null, src: null, pieces };
    added++;
  }
  if (done % 25 === 0 || done === missing.length) {
    flush();
    console.log(`… ${done}/${missing.length} backfilled, ${added} sets added`);
  }
}
flush();

console.log(`\nextra sets: ${Object.keys(sets).length} kept, ${Object.keys(dupes).length} journal/dead ids remembered`);
