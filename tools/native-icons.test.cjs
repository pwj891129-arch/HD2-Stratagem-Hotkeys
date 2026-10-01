const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {hash64} = require('./package.cjs');
const {readBundlesIndex, readChunks, entriesOf, readPackageRange, gameData} = require('./archive.cjs');

// Optional pinned-game reference regression; captures/assets are never packaged.
const reference = path.resolve(__dirname, '../scratch');
if (!fs.existsSync(path.join(reference, 'game-module.bin')) ||
    !fs.existsSync(path.join(reference, 'stratagem-settings.bin')) ||
    !fs.existsSync(path.join(gameData, 'bundles.nxa'))) {
  console.log('SKIP native icon reference test: local captures/game bundles unavailable');
  process.exit(0);
}
const image = fs.readFileSync(path.join(reference, 'game-module.bin'));
const settings = fs.readFileSync(path.join(reference, 'stratagem-settings.bin'));
const settingsAddress = Number(image.readBigUInt64LE(0x348e8f8));
const pictures = new Set();
let definitions = 0;
for (let kind = 1; kind < 149; kind++) {
  const offset = Number(image.readBigUInt64LE(0x37cb600 + kind * 8)) - settingsAddress;
  assert(offset >= 0 && offset + 400 <= settings.length, 'Captured definition bounds');
  const picture = settings.readBigUInt64LE(offset + 176);
  if (picture === 0n) continue;
  definitions++;
  pictures.add(picture.toString(16).padStart(16, '0'));
}
assert(pictures.size >= 100, 'Substantial native definition coverage, not mocked image hashes');
const debugId = hash64('core/performance_hud/debug').toString(16);
assert.equal(debugId, 'ccf39a02b444fa01', 'Old generic template was the debug font material');
assert(!pictures.has(debugId), 'No stratagem definition references the debug font material');
const packages = readBundlesIndex();
const opened = new Map();
function resources(packageId, type) {
  const parts = packages.get(packageId);
  assert(parts, 'Required native package');
  const first = parts[0];
  const filename = path.join(gameData, 'bundles.' + String(first.bundleIndex).padStart(2, '0') + '.nxa');
  if (!opened.has(filename)) opened.set(filename, readChunks(filename));
  const toc = opened.get(filename).resource(first.bundleOffset);
  return new Map(entriesOf(toc, packageId, hash64(type)).map(entry => [entry.id.padStart(16, '0'),
    {entry, parts}]));
}
try {
  const materials = resources('007e093ca718ca1a', 'material');
  const textures = resources('6a3eecfddce28fe8', 'texture');
  const debug = resources('9ba626afa44a3aa3', 'material').get(debugId);
  assert(debug, 'Native debug font material');
  const debugBytes = readPackageRange(opened, debug.parts, debug.entry.offset, debug.entry.size);
  for (const picture of pictures) {
    const native = materials.get(picture);
    assert(native, 'Definition +176 has native material ' + picture);
    assert(textures.has(picture), 'Native material owns corresponding texture ' + picture);
    const bytes = readPackageRange(opened, native.parts, native.entry.offset, native.entry.size);
    assert.equal(bytes.length, 160, 'Compiled native icon material layout');
    assert.equal(bytes.readUInt32LE(0), 0x120);
    assert.equal(bytes.readUInt32LE(128), 0x3461ff0d, 'Native image shader, not debug text shader');
    assert.notEqual(bytes.readUInt32LE(128), debugBytes.readUInt32LE(128));
    assert.equal(bytes.readUInt32LE(136), 0x3aa8b87e, 'Native diffuse binding');
    assert.equal(bytes.readBigUInt64LE(140).toString(16).padStart(16, '0'), picture,
      'Per-stratagem native material already binds its own texture');
  }
  console.log('PASS ' + definitions + ' nonzero native definitions / ' + pictures.size +
    ' distinct icon materials; native shader and matching textures verified read-only');
} finally {
  for (const bundle of opened.values()) bundle.close();
}
