const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const version = '0.1.11-test', resource = 'mods/hd2_helper/stratagem_hotkeys';
const luaType = 0xa14e8dfa2cd117e2n;
function hash64(value) {
  const data = Buffer.from(value), mix = 0xc6a4a7935bd1e995n, mask = 0xffffffffffffffffn;
  let h = BigInt(data.length) * mix & mask, at = 0;
  while (at + 8 <= data.length) {
    let k = data.readBigUInt64LE(at) * mix & mask;
    k ^= k >> 47n;
    h = (h ^ (k * mix & mask)) * mix & mask;
    at += 8;
  }
  if (at < data.length) {
    let tail = 0n;
    for (let i = at; i < data.length; i++) tail |= BigInt(data[i]) << BigInt((i - at) * 8);
    h = (h ^ tail) * mix & mask;
  }
  h ^= h >> 47n;
  h = h * mix & mask;
  return h ^ (h >> 47n);
}
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8').replace(/\r\n/g, '\n');
const source = read('addon.lua').replace('-- @PLATFORM@', () => read('platform.lua'))
  .replace('-- @READER@', () => read('reader.lua')).replace('-- @POLICY@', () => read('policy.lua'))
  .replace('-- @RADIAL@', () => read('radial.lua'));
assert.equal(source.split('\n')[0], `-- HD2-Addon: ${resource}`);
assert(!source.includes('-- @'));
assert(!/WriteProcessMemory|VirtualProtect|ffi\.cast\([^\n]+\)\s*\(/.test(source));
const body = Buffer.from(source), payload = Buffer.alloc(body.length + 8);
payload.writeUInt32LE(body.length, 0);
payload.writeUInt32LE(2, 4);
body.copy(payload, 8);
const archive = Buffer.alloc(Math.max(256, 192 + Math.ceil(payload.length / 16) * 16));
archive.writeUInt32LE(0xf0000011, 0);
archive.writeUInt32LE(1, 4);
archive.writeUInt32LE(1, 8);
archive.writeBigUInt64LE(BigInt(archive.length), 32);
archive.writeBigUInt64LE(luaType, 80);
archive.writeUInt32LE(1, 88);
archive.writeUInt32LE(16, 96);
archive.writeUInt32LE(16, 100);
archive.writeBigUInt64LE(hash64(resource), 104);
archive.writeBigUInt64LE(luaType, 112);
archive.writeBigUInt64LE(192n, 120);
archive.writeUInt32LE(payload.length, 160);
archive.writeUInt32LE(16, 172);
archive.writeUInt32LE(16, 176);
payload.copy(archive, 192);
const stage = path.join(__dirname, 'dist', `HD2-Stratagem-Hotkeys-${version}`);
fs.mkdirSync(path.join(stage, 'Addon'), {recursive: true});
fs.writeFileSync(path.join(__dirname, 'dist/stratagem_hotkeys.generated.lua'), source);
for (const [suffix, data] of [['', archive], ['.stream', Buffer.alloc(0)], ['.gpu_resources', Buffer.alloc(0)]]) {
  fs.writeFileSync(path.join(stage, 'Addon/9ba626afa44a3aa3.patch_0' + suffix), data);
}
const manifest = {Version: 1, Guid: '258a0830-aa77-402e-b899-6652f0297ef1',
  Name: `HD2 Stratagem Hotkeys ${version}`, Author: 'HD2 Helper',
  Description: 'Native RGB-mask stratagem icons with read-only atlas regions and game palette. Isolated owned GUI materials; missing metadata/resources fall back to names with diagnostic logs. Lua-only package, no icon assets or GUI binaries. Radial opens only after the character\'s game menu activates. Personal numbers match hotkeys 1-4. Arsenal-only settings. Requires Bingus Shared Loader v18 / API 1.',
  Options: []};
const pack = require('./tools/package.cjs');
const options = [
  ['radial', '원형 오버레이 ON/OFF', '캐릭터의 실제 스트라타젬 메뉴가 활성화된 경우에만 아이콘·이름·번호·대기시간을 표시합니다. 목록 열기 키를 누른 채 마우스로 고른 뒤 놓으면 커맨드를 입력합니다. 조준/투척은 수동입니다.', ['Addon']],
  ['hotkeys', 'Stratagem Hotkeys', '목록 열기 키 + 숫자열 1~4로 개인 장착 슬롯 커맨드를 입력합니다. 원형 메뉴에 표시된 개인 슬롯 번호와 매칭됩니다.', ['Addon']],
  ['shared', '공용/임무 스트라타젬 표시', '체크하면 공용/임무 스트라타젬도 원형 메뉴에 포함합니다. 개인 슬롯 번호 1~4는 유지하며 공용 항목에는 숫자 핫키를 표시하지 않습니다.', []],
  ['large', '큰 원형 메뉴', '체크하면 130%, 미체크하면 100% 크기입니다.', []],
  ['slow', '커맨드 입력: 30ms', '체크하면 누르기/떼기 최소 30ms, 미체크하면 15ms. 게임의 방향 입력 감지를 확인한 뒤 다음 키를 전송합니다.', []],
];
for (const [index, [name, label, description, extra]] of options.entries()) {
  const folder = 'Option_' + name;
  pack.write(path.join(stage, folder), index + 2, [pack.lua('mods/hd2_helper/stratagem_option_' + name, 'return true\n')]);
  manifest.Options.push({Name: label, Description: description, Include: [...extra, folder]});
}
// Icons bind already-loaded native atlas regions and palettes to owned GUI instances.
assert(!fs.existsSync(path.join(stage, 'Icons')), 'Stale icon resources must not ship');
fs.writeFileSync(path.join(stage, 'manifest.json'), JSON.stringify(manifest, null, 2));
for (const file of ['README.md', 'THIRD_PARTY.txt']) fs.copyFileSync(path.join(__dirname, file), path.join(stage, file));
assert.equal(archive.readBigUInt64LE(104), hash64(resource));
assert.equal(archive.readBigUInt64LE(80), luaType);
assert.equal(archive.readBigUInt64LE(32), BigInt(archive.length));
assert.equal(archive.readUInt32LE(160), payload.length);
console.log(`Built ${stage}`);
console.log(`Lua resource ${hash64(resource).toString(16)}; ${body.length} bytes; archive SHA256 ${crypto.createHash('sha256').update(archive).digest('hex')}`);
