const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const pack = require('./package.cjs');

// Regression: the old 224-byte flag archive was below the SDK's minimum size.
function checkMinimum(bytes) {
  assert(bytes.length >= 256 * bytes.readUInt32LE(8), 'Archive below native minimum size');
}
const oldMarker = Buffer.alloc(224);
oldMarker.writeUInt32LE(1, 8);
assert.throws(() => checkMinimum(oldMarker), /below native minimum/);
for (const count of [1, 2, 3, 16]) {
  const entries = Array.from({length: count}, (_, index) => pack.lua('test/flag_' + index, 'return true\n'));
  const bytes = pack.archive(entries);
  checkMinimum(bytes);
  assert.equal(bytes.length, 256 * count);
  assert.equal(bytes.readBigUInt64LE(32), BigInt(bytes.length));
  let end = 0;
  for (let index = 0; index < count; index++) {
    const at = 104 + 80 * index;
    const offset = Number(bytes.readBigUInt64LE(at + 16)), size = bytes.readUInt32LE(at + 56);
    assert.equal(bytes.subarray(offset + 8, offset + size).toString('utf8'), 'return true\n');
    end = Math.max(end, offset + size);
  }
  assert(bytes.subarray(end).every(value => value === 0), 'Padding must not contain resources');
}
const large = pack.archive([pack.lua('test/large', 'x'.repeat(8192))]);
checkMinimum(large);
assert.equal(large.length, 192 + Math.ceil((8192 + 8) / 16) * 16);

const stage = path.resolve(__dirname, '../dist/HD2-Stratagem-Hotkeys-0.1.3-test');
const manifest = JSON.parse(fs.readFileSync(path.join(stage, 'manifest.json'), 'utf8'));
const folders = [...new Set(manifest.Options.flatMap(option => option.Include))];
const ids = new Set();
assert.equal(manifest.Options.length, 6);
assert.equal(folders.length, 7);
assert(!fs.existsSync(path.join(stage, 'Icons')));
for (const folder of folders) {
  const files = fs.readdirSync(path.join(stage, folder));
  const patches = files.filter(name => /\.patch_\d+$/.test(name));
  assert.equal(patches.length, 1);
  for (const name of patches) {
    const archive = fs.readFileSync(path.join(stage, folder, name));
    checkMinimum(archive);
    assert.equal(archive.readUInt32LE(0), 0xf0000011);
    assert.equal(archive.readUInt32LE(4), 1);
    assert.equal(archive.readUInt32LE(8), 1);
    assert.equal(archive.readBigUInt64LE(80), pack.hash64('lua'));
    assert.equal(archive.readBigUInt64LE(112), pack.hash64('lua'));
    assert.equal(archive.readBigUInt64LE(32), BigInt(archive.length));
    const id = archive.readBigUInt64LE(104).toString(16);
    assert(!ids.has(id)); ids.add(id);
    const offset = Number(archive.readBigUInt64LE(120)), size = archive.readUInt32LE(160);
    assert(offset + size <= archive.length);
    assert.equal(archive.readUInt32LE(offset + 4), 2);
    assert.equal(archive.readUInt32LE(offset), size - 8);
    const source = archive.subarray(offset + 8, offset + size).toString('utf8');
    if (folder === 'Addon') {
      assert(source.startsWith('-- HD2-Addon: mods/hd2_helper/stratagem_hotkeys\n'));
      assert(source.includes('BOOT 0.1.3-test'));
      assert(!source.includes('-- @'));
      assert(!/radial_icon_|set_texture|Gui\.material/.test(source));
    } else {
      assert.equal(archive.length, 256);
      assert.equal(source, 'return true\n');
      assert.equal(id, pack.hash64('mods/hd2_helper/stratagem_option_' + folder.slice(7)).toString(16));
    }
    for (const suffix of ['.stream', '.gpu_resources']) {
      assert.equal(fs.statSync(path.join(stage, folder, name + suffix)).size, 0);
    }
  }
}
console.log('PASS minimum-size regressions and 7 unique Lua-only archives; options are 256 bytes');
