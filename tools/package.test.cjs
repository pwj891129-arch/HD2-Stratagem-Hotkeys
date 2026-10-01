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

const stage = path.resolve(__dirname, '../dist/HD2-Stratagem-Hotkeys-0.1.9-test');
const manifest = JSON.parse(fs.readFileSync(path.join(stage, 'manifest.json'), 'utf8'));
const folders = [...new Set(manifest.Options.flatMap(option => option.Include))];
const ids = new Set();
assert.equal(manifest.Options.length, 5);
assert.equal(folders.length, 6);
assert(!folders.includes('Option_f6'));
assert(!manifest.Options.some(option => option.Name.includes('F6')));
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
      assert(source.includes('BOOT 0.1.9-test'));
      assert(source.includes('reader:game_menu()'));
      assert(source.includes('game-stratagem-menu-closed'));
      assert(source.includes('tostring(row.slot)'));
      assert(!source.includes('self:text(tostring(index)'));
      assert(source.includes('INPUT waiting-list-close'));
      assert(source.includes('command-input-observed; game-result-unverified'));
      assert(!source.includes('command-sent; game-result-unverified'));
      assert(source.includes('Policy.new(channel.command_key'));
      assert(source.includes('reader:command_state(binding)'));
      assert(source.includes('game-direction-not-observed step='));
      assert(source.includes('self.sr.Gui.resolution()'));
      assert(!/Gui\.resolution\(\s*[^)\s]/.test(source), 'Gui.resolution takes no GUI object');
      assert(source.includes('OVERLAY stage='));
      assert(source.includes('WAIT list-key-release'));
      assert(!source.includes('option("f6"'));
      assert(!source.includes('-- @'));
      assert(source.includes('sr.Application.can_get("texture", art)'));
      assert(source.includes('pcall(sr.Gui.material, gui, self.icon_material)'));
      assert(source.includes('pcall(sr.Material.set_texture, icon.material'));
      assert(source.includes('pcall(sr.Gui.bitmap, icon.gui'));
      assert(source.includes('OVERLAY icons='));
      assert(!/radial_icon_|create_material|set_resource_override/.test(source));
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
console.log('PASS minimum-size regressions and 6 unique Lua-only archives; no F6 option');
