const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
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
const align = value => Math.ceil(value / 16) * 16;
function archive(entries) {
  entries = [...entries].sort((a, b) => a.type < b.type ? -1 : a.type > b.type ? 1 : a.id < b.id ? -1 : 1);
  const types = [...new Set(entries.map(entry => entry.type))];
  const header = 72 + types.length * 32;
  let offset = align(header + entries.length * 80);
  for (const entry of entries) { entry.offset = offset; offset = align(offset + entry.data.length); }
  const bytes = Buffer.alloc(offset);
  bytes.writeUInt32LE(0xf0000011, 0);
  bytes.writeUInt32LE(types.length, 4);
  bytes.writeUInt32LE(entries.length, 8);
  bytes.writeBigUInt64LE(BigInt(offset), 32);
  types.forEach((type, index) => {
    const at = 72 + index * 32;
    bytes.writeBigUInt64LE(type, at + 8);
    bytes.writeUInt32LE(entries.filter(entry => entry.type === type).length, at + 16);
    bytes.writeUInt32LE(16, at + 24); bytes.writeUInt32LE(16, at + 28);
  });
  entries.forEach((entry, index) => {
    const at = header + index * 80;
    bytes.writeBigUInt64LE(entry.id, at); bytes.writeBigUInt64LE(entry.type, at + 8);
    bytes.writeBigUInt64LE(BigInt(entry.offset), at + 16);
    bytes.writeUInt32LE(entry.data.length, at + 56);
    bytes.writeUInt32LE(16, at + 68); bytes.writeUInt32LE(16, at + 72);
    entry.data.copy(bytes, entry.offset);
  });
  return bytes;
}
function lua(name, source) {
  const body = Buffer.from(source), data = Buffer.alloc(body.length + 8);
  data.writeUInt32LE(body.length, 0); data.writeUInt32LE(2, 4); body.copy(data, 8);
  return {id: hash64(name), type: hash64('lua'), data};
}
function write(folder, number, entries) {
  fs.mkdirSync(folder, {recursive: true});
  const file = path.join(folder, `9ba626afa44a3aa3.patch_${number}`);
  const bytes = archive(entries);
  fs.writeFileSync(file, bytes);
  for (const suffix of ['.stream', '.gpu_resources']) fs.writeFileSync(file + suffix, Buffer.alloc(0));
  assert.equal(bytes.readBigUInt64LE(32), BigInt(bytes.length));
  return bytes;
}
function vanillaMaterial() {
  const reader = require('./archive.cjs');
  const parts = reader.readBundlesIndex().get('9ba626afa44a3aa3'), opened = new Map();
  try {
    const file = path.join(reader.gameData, `bundles.${String(parts[0].bundleIndex).padStart(2, '0')}.nxa`);
    opened.set(file, reader.readChunks(file));
    const toc = opened.get(file).resource(parts[0].bundleOffset);
    const entry = reader.entriesOf(toc, '9ba626afa44a3aa3', hash64('material')).find(item => item.id === 'ccf39a02b444fa01');
    assert(entry && entry.size === 160, 'Native GUI material changed');
    const bytes = reader.readPackageRange(opened, parts, entry.offset, entry.size);
    assert.equal(bytes.readUInt32LE(0), 0x120);
    assert(bytes.includes(Buffer.from('7eb8a83a', 'hex')), 'Native GUI texture slot changed');
    return bytes;
  } finally { for (const bundle of opened.values()) bundle.close(); }
}
module.exports = {hash64, archive, lua, write, vanillaMaterial};
