// check-lua.mjs — parse every .lua file under EasySetCollection/ with luaparse to
// catch syntax errors (WoW uses a Lua 5.1 dialect).
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';
import luaparse from 'luaparse';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIR = join(__dirname, '..', 'EasySetCollection');

function walk(dir) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (e.name.endsWith('.lua')) out.push(p);
  }
  return out;
}

const files = walk(DIR).sort();
let failures = 0;
for (const f of files) {
  const src = readFileSync(f, 'utf8');
  const rel = relative(DIR, f);
  try {
    luaparse.parse(src, { luaVersion: '5.1' });
    console.log(`OK   ${rel}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${rel}: ${e.message}`);
  }
}
console.log(failures ? `\n${failures} file(s) failed.` : `\nAll ${files.length} files parsed OK.`);
process.exit(failures ? 1 : 0);
