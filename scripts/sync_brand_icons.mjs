#!/usr/bin/env node
// Package the approved master image into platform icon sizes without changing its design.
// Uses macOS sips; no image-generation credentials or third-party dependencies.
import { readFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const master = resolve(root, 'app/assets/brand/jem-calc-logo.png');
function resize(size, relative) {
  const output = resolve(root, relative);
  mkdirSync(dirname(output), { recursive: true });
  execFileSync('sips', ['-z', String(size), String(size), master, '--out', output], { stdio: 'pipe' });
}

for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  resize(size, `app/android/app/src/main/res/mipmap-${density}/ic_launcher.png`);
}
resize(432, 'app/android/app/src/main/res/drawable-nodpi/jem_launcher_foreground.png');
const catalog = 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
const { images } = JSON.parse(readFileSync(resolve(root, catalog, 'Contents.json')));
const generated = new Set();
for (const icon of images) {
  if (!icon.filename || generated.has(icon.filename)) continue;
  resize(Math.round(parseFloat(icon.size) * parseFloat(icon.scale)), `${catalog}/${icon.filename}`);
  generated.add(icon.filename);
}
for (const size of [192, 512]) resize(size, `app/web/icons/jem-calc-${size}.png`);
resize(180, 'app/web/icons/apple-touch-icon.png');
resize(48, 'app/web/favicon.png');
console.log(`Packaged brand icons: 5 Android + adaptive, ${generated.size} iOS, 4 web.`);
