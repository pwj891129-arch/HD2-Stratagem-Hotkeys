const fs = require('node:fs');
const path = require('node:path');
const { readBundlesIndex, readChunks, entriesOf, readPackageRange, gameData } = require('./archive.cjs');
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
const id = hash64('content/input').toString(16), type = hash64('config');
const packages = readBundlesIndex(), opened = new Map();
try {
  for (const [name, parts] of packages) {
    if (!/^[0-9a-f]{16}$/.test(name) || !parts.length) continue;
    const first = parts[0];
    const file = path.join(gameData, `bundles.${String(first.bundleIndex).padStart(2, '0')}.nxa`);
    if (!opened.has(file)) opened.set(file, readChunks(file));
    const toc = opened.get(file).resource(first.bundleOffset);
    const entry = entriesOf(toc, name, type).find(entry => entry.id === id);
    if (entry) {
      const data = readPackageRange(opened, parts, entry.offset, entry.size);
      fs.mkdirSync(path.join(__dirname, '../scratch'), { recursive: true });
      fs.writeFileSync(path.join(__dirname, '../scratch/input.config'), data);
      console.log(`Read content/input.config: ${data.length} bytes`);
      break;
    }
  }
} finally {
  for (const bundle of opened.values()) bundle.close();
}
