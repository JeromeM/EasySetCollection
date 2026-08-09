#!/usr/bin/env node
// gen-icons.mjs — DEV-ONLY: draw the flat header icons programmatically and
// write them as uncompressed 32-bit TGAs (the format WoW loads natively):
//   Media/settings.tga — flat gear (8 teeth, ring body, center hole)
//   Media/setup.tga    — magic wand + sparkles (the setup wizard)
// Icons are white with an anti-aliased alpha channel (16x supersampling);
// the UI tints them with SetVertexColor. Rerun after tweaking the shapes:
//   node scripts/gen-icons.mjs        (prints an ASCII preview of each icon)

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MEDIA = join(__dirname, '..', 'EasySetCollection', 'Media');

const SIZE = 64;   // final texture size (power of two)
const SS = 4;      // supersampling factor per axis (16 samples per pixel)

// --- shapes (logical space: x,y in [-1,1], +y up) ---------------------------------

// flat gear: 8 teeth around a ring body with a punched center hole
function gear(x, y) {
  const r = Math.hypot(x, y);
  if (r < 0.34) return false;                 // center hole
  if (r <= 0.60) return true;                 // body ring
  if (r > 0.92) return false;
  // teeth centered every 45°, slightly tapered toward the tip
  const per = Math.PI / 4;
  const theta = Math.atan2(y, x);
  const d = Math.abs(((theta % per) + per * 1.5) % per - per / 2);
  const half = 0.20 - 0.06 * (r - 0.60) / 0.32;
  return d <= half;
}

// distance from point to segment
function segDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

// four-pointed sparkle (astroid): |x|^(2/3) + |y|^(2/3) <= s^(2/3)
function sparkle(px, py, cx, cy, s) {
  const x = Math.abs(px - cx) / s, y = Math.abs(py - cy) / s;
  return Math.cbrt(x * x) + Math.cbrt(y * y) <= 1;
}

// magic wand pointing top-right, one clean four-pointed star off the tip
// (smaller accents vanish at the 14px display size)
function wand(x, y) {
  if (segDist(x, y, -0.68, -0.68, 0.14, 0.14) <= 0.13) return true;
  return sparkle(x, y, 0.48, 0.48, 0.46);
}

// --- raster + TGA ------------------------------------------------------------------

// coverage map via supersampling: SIZE x SIZE floats in [0,1], row 0 = top
function render(inside) {
  const cov = new Float32Array(SIZE * SIZE);
  for (let row = 0; row < SIZE; row++) {
    for (let col = 0; col < SIZE; col++) {
      let hits = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const x = ((col + (sx + 0.5) / SS) / SIZE) * 2 - 1;
          const y = 1 - ((row + (sy + 0.5) / SS) / SIZE) * 2;
          if (inside(x, y)) hits++;
        }
      }
      cov[row * SIZE + col] = hits / (SS * SS);
    }
  }
  return cov;
}

// uncompressed true-color TGA, 32bpp BGRA, bottom-left origin
function writeTGA(path, cov) {
  const header = Buffer.alloc(18);
  header[2] = 2;                    // uncompressed true-color
  header.writeUInt16LE(SIZE, 12);   // width
  header.writeUInt16LE(SIZE, 14);   // height
  header[16] = 32;                  // bits per pixel
  header[17] = 8;                   // 8 alpha bits, bottom-left origin
  const px = Buffer.alloc(SIZE * SIZE * 4);
  let o = 0;
  for (let row = SIZE - 1; row >= 0; row--) {      // bottom-up
    for (let col = 0; col < SIZE; col++) {
      const a = Math.round(cov[row * SIZE + col] * 255);
      px[o++] = 255; px[o++] = 255; px[o++] = 255;  // B G R (white, tinted in-game)
      px[o++] = a;
    }
  }
  writeFileSync(path, Buffer.concat([header, px]));
}

function preview(name, cov) {
  const RAMP = ' ░▒▓█';
  console.log(`\n${name}:`);
  for (let row = 0; row < SIZE; row += 2) {         // 2 rows per text line
    let line = '';
    for (let col = 0; col < SIZE; col++) {
      const a = (cov[row * SIZE + col] + cov[(row + 1) * SIZE + col]) / 2;
      line += RAMP[Math.min(4, Math.floor(a * 4.999))];
    }
    console.log(line);
  }
}

for (const [file, shape] of [['settings.tga', gear], ['setup.tga', wand]]) {
  const cov = render(shape);
  writeTGA(join(MEDIA, file), cov);
  preview(file, cov);
  console.log(`-> Media/${file}`);
}
