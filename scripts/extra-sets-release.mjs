#!/usr/bin/env node
// extra-sets-release.mjs — CI helper for the weekly extra-sets refresh
// (.github/workflows/extra-sets.yml). Compares the fresh harvest against the
// previous one, decides what kind of week it is, and prepares the release:
//
//   mode=none    nothing changed — the workflow stops quietly.
//   mode=release additions/updates only — bumps the .toc to the next DATA
//                version (X.Y.Z -> X.Y.Z.1, X.Y.Z.W -> X.Y.Z.W+1) and writes
//                data/extra-release-notes.md (release.yml picks it up when
//                the CHANGELOG has no section for the version — data releases
//                deliberately never touch CHANGELOG.md).
//   mode=review  sets DISAPPEARED from the harvest — suspicious (Wowhead
//                hiccup or reorganization): no release, the workflow opens a
//                review PR with the same notes file as body.
//
// Usage : node scripts/extra-sets-release.mjs <previous extra-sets.json>
// Emits : GitHub outputs (mode, version, added, removed, changed) to
//         $GITHUB_OUTPUT — printed to stdout when unset (local dry runs).

import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const TOC = join(ROOT, 'EasySetCollection', 'EasySetCollection.toc');
const NEW = join(ROOT, 'data', 'extra-sets.json');
const NOTES = join(ROOT, 'data', 'extra-release-notes.md');

const EXP_NAMES = ['Classic', 'The Burning Crusade', 'Wrath of the Lich King',
  'Cataclysm', 'Mists of Pandaria', 'Warlords of Draenor', 'Legion',
  'Battle for Azeroth', 'Shadowlands', 'Dragonflight', 'The War Within', 'Midnight'];
const MAX_LISTED = 60;

const oldPath = process.argv[2];
if (!oldPath) { console.error('usage: extra-sets-release.mjs <previous extra-sets.json>'); process.exit(2); }
const oldSets = (JSON.parse(readFileSync(oldPath, 'utf8')).sets) || {};
const newSets = (JSON.parse(readFileSync(NEW, 'utf8')).sets) || {};

const added = [], removed = [], changed = [];
for (const id of Object.keys(newSets)) {
  if (!(id in oldSets)) added.push(id);
  else if (JSON.stringify(newSets[id]) !== JSON.stringify(oldSets[id])) changed.push(id);
}
for (const id of Object.keys(oldSets)) {
  if (!(id in newSets)) removed.push(id);
}

function output(k, v) {
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${k}=${v}\n`);
  else console.log(`${k}=${v}`);
}

function bullet(id, sets) {
  const s = sets[id];
  const exp = s.exp != null && EXP_NAMES[s.exp - 1] ? ` *(${EXP_NAMES[s.exp - 1]})*` : '';
  return `- ${s.name}${exp}`;
}

const mode = removed.length > 0 ? 'review'
  : (added.length + changed.length > 0) ? 'release' : 'none';
output('mode', mode);
output('added', added.length);
output('removed', removed.length);
output('changed', changed.length);
console.log(`extra-sets diff: +${added.length} / -${removed.length} / ~${changed.length} -> ${mode}`);
if (mode === 'none') process.exit(0);

// --- release notes -----------------------------------------------------------------
const lines = [];
if (mode === 'review') {
  lines.push(`### Weekly harvest needs review: ${removed.length} set(s) disappeared`, '');
  for (const id of removed.slice(0, MAX_LISTED)) lines.push(bullet(id, oldSets));
  if (removed.length > MAX_LISTED) lines.push(`- …and ${removed.length - MAX_LISTED} more`);
  if (added.length) {
    lines.push('', `Also ${added.length} addition(s):`, '');
    for (const id of added.slice(0, MAX_LISTED)) lines.push(bullet(id, newSets));
  }
} else {
  lines.push(`Weekly data update: ${added.length} new out-of-journal set(s).`, '');
  for (const id of added.slice(0, MAX_LISTED)) lines.push(bullet(id, newSets));
  if (added.length > MAX_LISTED) lines.push(`- …and ${added.length - MAX_LISTED} more`);
  if (changed.length) lines.push('', `${changed.length} existing set(s) updated (pieces or metadata).`);
}
lines.push('');
writeFileSync(NOTES, lines.join('\n'));

// --- version bump (release mode only) ------------------------------------------------
if (mode === 'release') {
  const toc = readFileSync(TOC, 'utf8');
  const m = toc.match(/^## Version:[ \t]*(\d+\.\d+\.\d+)(?:\.(\d+))?[ \t]*\r?$/m);
  if (!m) { console.error('cannot parse ## Version in the .toc'); process.exit(2); }
  const version = `${m[1]}.${Number(m[2] || 0) + 1}`;
  writeFileSync(TOC, toc.replace(m[0], m[0].replace(/(\d+\.\d+\.\d+)(\.\d+)?/, version)));
  output('version', version);
  console.log(`data version: ${version}`);
}
