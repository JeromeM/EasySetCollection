#!/usr/bin/env node
// fetch-quest-sources.mjs — DEV-ONLY one-off: resolve item -> questID for the
// quest pieces the in-game scan couldn't match (the server only serves reward
// data for recent/world quests, so /esc genquests caps out on old content).
//
// Source: Wowhead's public item XML feed. For quest-reward items the <json>
// blob carries `"source":[4]` and a sourcemore entry `{"t":5,"ti":<questID>}`.
// Only t=5 (quest) entries are taken, so items the client mislabels as quest
// rewards simply stay unmatched instead of getting a wrong ID.
//
// Reads  : data/sets-export.lua   (quest pieces + in-game questRewards)
//          data/quest-sources.json (previous runs — resumable, misses cached)
// Writes : data/quest-sources.json { itemID: questID | null }
// Usage  : node scripts/fetch-quest-sources.mjs   (throttled ~4 req/s)
//
// build-sets.mjs merges this file with the in-game questRewards (in-game wins).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import luaparse from 'luaparse';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const SRC = join(ROOT, 'data', 'sets-export.lua');
const OUT = join(ROOT, 'data', 'quest-sources.json');

const THROTTLE_MS = 1000;        // gentle: CloudFront hard-blocks bursty clients
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

const targets = new Set();
for (const rec of sets) {
  const pieces = Array.isArray(rec.pieces) ? rec.pieces : Object.values(rec.pieces || {});
  for (const p of pieces) {
    if (p.st === 2 && p.itemID != null
        && ingame[p.itemID] == null           // the in-game scan already has it
        && !(p.itemID in known)) {            // fetched previously (hit or miss)
      targets.add(p.itemID);
    }
  }
}

console.log(`quest pieces to resolve via Wowhead: ${targets.size}`
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

let done = 0, found = 0, consecutiveFails = 0;
for (const itemID of targets) {
  const questID = await fetchQuestID(itemID);
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
    known[itemID] = questID;   // null too: caches the definitive miss
    if (questID) found++;
  }
  if (done % 50 === 0 || done === targets.size) {
    writeFileSync(OUT, JSON.stringify(known, null, 0));
    console.log(`… ${done}/${targets.size} fetched, ${found} quest matches this run`);
  }
  await sleep(THROTTLE_MS);
}
writeFileSync(OUT, JSON.stringify(known, null, 0));

const totalKnown = Object.values(known).filter((v) => v != null).length;
console.log(`done: ${found} new matches this run; quest-sources.json now maps ${totalKnown} items.`);
