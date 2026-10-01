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
  assert(settings.readUInt32LE(offset + 184) <= 4, 'Native five-entry icon palette bounds');
  definitions++;
  pictures.add(picture.toString(16).padStart(16, '0'));
}
assert(pictures.size >= 100, 'Substantial native definition coverage, not mocked image hashes');
const debugId = hash64('core/performance_hud/debug').toString(16);
assert.equal(debugId, 'ccf39a02b444fa01', 'Old generic template was the debug font material');
assert(!pictures.has(debugId), 'No stratagem definition references the debug font material');
assert.equal(image.subarray(0x1893650, 0x1893657).toString('hex'), '488b97b0000000',
  'Native tile reads definition +176 as texture');
for (const [at, target] of [[0x1893670, 0x331b610], [0x1893695, 0x21e89e0], [0x18936b3, 0x21e8a10]]) {
  assert.equal(at + 7 + image.readInt32LE(at + 3), target, 'Native tile shader color address');
}
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
  const mask = materials.get('c0f3797849262087');
  assert(mask, 'Native RGB-mask GUI material');
  const maskBytes = readPackageRange(opened, mask.parts, mask.entry.offset, mask.entry.size);
  assert.equal(maskBytes.readBigUInt64LE(140), 0n, 'Mask material requires runtime texture binding');
  assert.notEqual(maskBytes.readUInt32LE(128), debugBytes.readUInt32LE(128));
  for (const picture of pictures) {
    const native = materials.get(picture);
    assert(native, 'Definition +176 has native material ' + picture);
    assert(textures.has(picture), 'Native material owns corresponding texture ' + picture);
    const bytes = readPackageRange(opened, native.parts, native.entry.offset, native.entry.size);
    assert.equal(bytes.length, 160, 'Compiled native icon material layout');
    assert.equal(bytes.readUInt32LE(0), 0x120);
    assert.equal(bytes.readUInt32LE(128), 0x3461ff0d, 'Native image material program');
    assert.equal(bytes.readUInt32LE(128), maskBytes.readUInt32LE(128),
      'Shared image program still needs native atlas/color setup');
    assert.notEqual(bytes.readUInt32LE(128), debugBytes.readUInt32LE(128));
    assert.equal(bytes.readUInt32LE(136), 0x3aa8b87e, 'Native diffuse binding');
    assert.equal(bytes.readBigUInt64LE(140).toString(16).padStart(16, '0'), picture,
      'Per-stratagem native material already binds its own texture');
  }
  const queryFile = path.join(reference, 'icon-reference/texture.bin');
  if (fs.existsSync(queryFile)) {
    const query = fs.readFileSync(queryFile);
    assert.equal(query.subarray(5, 8).toString('hex'), '488b05');
    assert.equal(0x3438e0 + 12 + query.readInt32LE(8), 0x1a10238, 'Pinned EXE atlas resource root');
    assert(query.includes(Buffer.from('498b80f8030000', 'hex')) ||
      query.includes(Buffer.from('4c8b80f8030000', 'hex')), 'Native resource manager +0x3f8');
    assert(query.includes(Buffer.from('498b80a0020000', 'hex')) ||
      query.includes(Buffer.from('4d8b80a0020000', 'hex')) ||
      query.includes(Buffer.from('4c8b80a0020000', 'hex')), 'Native atlas rows +0x2a0');
    assert.equal(query.subarray(0x35, 0x3c).toString('hex'), '41f7b0b4020000',
      'Native bucket divisor is manager +0x2b4');
    assert.equal(query.subarray(0x60, 0x79).toString('hex'),
      '8bc2488d0c404d3b14c87453418b54c81081faffffff7f75e7',
      'Native chain follows full next DWORD until sentinel, not the bucket divisor');
  }
  console.log('PASS ' + definitions + ' nonzero native definitions / ' + pictures.size +
    ' distinct textures; native RGB-mask template, palette and atlas code verified read-only');
} finally {
  for (const bundle of opened.values()) bundle.close();
}
