const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const pack = require('./package.cjs');

const stage = path.resolve(__dirname, '../dist/HD2-Stratagem-Hotkeys-0.1.2-test');
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
      assert(source.includes('BOOT 0.1.2-test'));
      assert(!source.includes('-- @'));
      assert(!/radial_icon_|set_texture|Gui\.material/.test(source));
    } else {
      assert.equal(source, 'return true\n');
      assert.equal(id, pack.hash64('mods/hd2_helper/stratagem_option_' + folder.slice(7)).toString(16));
    }
    for (const suffix of ['.stream', '.gpu_resources']) {
      assert.equal(fs.statSync(path.join(stage, folder, name + suffix)).size, 0);
    }
  }
}
console.log('PASS 7 unique Lua-only archives; no startup icon material resources');
