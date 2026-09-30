const fs = require('node:fs');
const path = require('node:path');

const gameData = path.resolve(__dirname, '..', '..', 'data');
const networkConfigType = 0x3b1fa9e8f6bac374n;

function lz4Block(input, size) {
  const output = Buffer.alloc(size);
  let source = 0;
  let target = 0;
  while (source < input.length) {
    const token = input[source++];
    let literal = token >>> 4;
    if (literal === 15) {
      let extra;
      do { extra = input[source++]; literal += extra; } while (extra === 255);
    }
    if (source + literal > input.length || target + literal > size) {
      throw new Error('Invalid LZ4 literal length');
    }
    input.copy(output, target, source, source + literal);
    source += literal;
    target += literal;
    if (source === input.length) break;
    if (source + 2 > input.length) throw new Error('Missing LZ4 match offset');
    const offset = input.readUInt16LE(source);
    source += 2;
    if (offset < 1 || offset > target) throw new Error('Invalid LZ4 match offset');
    let match = (token & 15) + 4;
    if ((token & 15) === 15) {
      let extra;
      do { extra = input[source++]; match += extra; } while (extra === 255);
    }
    if (target + match > size) throw new Error('Invalid LZ4 match length');
    for (let index = 0; index < match; index++) {
      output[target + index] = output[target + index - offset];
    }
    target += match;
  }
  if (target !== size) throw new Error(`LZ4 size mismatch: ${target} != ${size}`);
  return output;
}

function readChunks(file) {
  const fd = fs.openSync(file, 'r');
  const header = Buffer.alloc(32);
  fs.readSync(fd, header, 0, header.length, 0);
  if (header.readUInt32LE(0) !== 0x52415344) {
    fs.closeSync(fd);
    throw new Error(`Not a DSAR bundle: ${file}`);
  }
  const count = header.readUInt32LE(8);
  const table = Buffer.alloc(count * 32);
  fs.readSync(fd, table, 0, table.length, 32);
  const chunks = [];
  for (let index = 0; index < count; index++) {
    const at = index * 32;
    chunks.push({
      uncompressedOffset: Number(table.readBigUInt64LE(at)),
      compressedOffset: Number(table.readBigUInt64LE(at + 8)),
      uncompressedSize: table.readUInt32LE(at + 16),
      compressedSize: table.readUInt32LE(at + 20),
      compression: table[at + 24], flags: table[at + 25],
    });
  }
  function load(index) {
    const entry = chunks[index];
    const bytes = Buffer.alloc(entry.compressedSize);
    fs.readSync(fd, bytes, 0, bytes.length, entry.compressedOffset);
    if (entry.compression === 0) return bytes;
    if (entry.compression === 3) return lz4Block(bytes, entry.uncompressedSize);
    throw new Error(`Unknown compression ${entry.compression}`);
  }
  function resource(offset) {
    const start = chunks.findIndex(entry => entry.uncompressedOffset === offset);
    if (start < 0) throw new Error(`Bundle offset ${offset} missing: ${file}`);
    const parts = [];
    for (let index = start; index < chunks.length; index++) {
      if (index > start && (chunks[index].flags & 2)) break;
      parts.push(load(index));
    }
    return Buffer.concat(parts);
  }
  return { chunks, load, resource, close: () => fs.closeSync(fd) };
}

function readBundlesIndex() {
  const bundle = readChunks(path.join(gameData, 'bundles.nxa'));
  const bytes = Buffer.concat(bundle.chunks.map((_, index) => bundle.load(index)));
  bundle.close();
  const packages = new Map();
  const count = bytes.readUInt32LE(16);
  for (let index = 0; index < count; index++) {
    const at = 24 + index * 24;
    const nameOffset = bytes.readUInt32LE(at + 8);
    const end = bytes.indexOf(0, nameOffset);
    const name = bytes.toString('utf8', nameOffset, end);
    const itemCount = bytes.readUInt32LE(at + 12);
    const itemOffset = bytes.readUInt32LE(at + 16);
    const parts = [];
    for (let item = 0; item < itemCount; item++) {
      const entry = itemOffset + item * 16;
      parts.push({ archiveOffset: Number(bytes.readBigUInt64LE(entry)),
        bundleOffset: bytes.readUInt32LE(entry + 8),
        bundleIndex: bytes[entry + 15] });
    }
    packages.set(name, parts);
  }
  return packages;
}

function entriesOf(toc, file, resourceType = networkConfigType) {
  if (toc.readUInt32LE(0) !== 0xf0000011) {
    throw new Error(`Invalid package TOC: ${file}`);
  }
  const count = toc.readUInt32LE(8);
  const start = 72 + toc.readUInt32LE(4) * 32;
  const entries = [];
  for (let index = 0; index < count; index++) {
    const at = start + index * 80;
    if (at + 80 > toc.length) throw new Error(`Truncated package TOC: ${file}`);
    if (toc.readBigUInt64LE(at + 8) === resourceType) {
      entries.push({ file, id: toc.readBigUInt64LE(at).toString(16),
        offset: Number(toc.readBigUInt64LE(at + 16)),
        size: toc.readUInt32LE(at + 56) });
    }
  }
  return entries;
}

function readPackageRange(opened, parts, offset, size) {
  const end = offset + size;
  const slices = [];
  for (let index = 0; index < parts.length; index++) {
    const part = parts[index];
    const next = parts[index + 1];
    const partEnd = next ? next.archiveOffset : end;
    if (partEnd <= offset || part.archiveOffset >= end) continue;
    const filename = path.join(gameData, `bundles.${String(part.bundleIndex).padStart(2, '0')}.nxa`);
    if (!opened.has(filename)) opened.set(filename, readChunks(filename));
    const bundle = opened.get(filename);
    let position = part.archiveOffset;
    let bundleOffset = part.bundleOffset;
    while (position < partEnd && position < end) {
      const data = bundle.resource(bundleOffset);
      const from = Math.max(0, offset - position);
      const to = Math.min(data.length, end - position, partEnd - position);
      if (to > from) slices.push(data.subarray(from, to));
      position += data.length;
      bundleOffset += data.length;
    }
  }
  const bytes = Buffer.concat(slices);
  if (bytes.length !== size) throw new Error(`Package range mismatch: ${bytes.length} != ${size}`);
  return bytes;
}

function main() {
  const packages = readBundlesIndex();
  const found = [];
  const opened = new Map();
  for (const [name, parts] of packages) {
    if (!/^[0-9a-f]{16}$/.test(name)) continue;
    if (parts.length === 0) continue;
    const first = parts[0];
    const filename = path.join(gameData, `bundles.${String(first.bundleIndex).padStart(2, '0')}.nxa`);
    if (!opened.has(filename)) opened.set(filename, readChunks(filename));
    const toc = opened.get(filename).resource(first.bundleOffset);
    for (const entry of entriesOf(toc, name)) {
      const bytes = readPackageRange(opened, parts, entry.offset, entry.size);
      entry.head = bytes.subarray(0, 64).toString('hex');
      entry.printable = bytes.toString('latin1').match(/[ -~]{8,}/g)?.slice(0, 12) || [];
      entry.samples = {};
      for (const name of ['jq39fx', '4fqtox', 'gbgqot6', 'gl7xl2w',
        'weapon', 'ammo', 'magazines', 'overheated', 'laser_rifle']) {
        entry.samples[name] = bytes.indexOf(Buffer.from(name));
      }
      entry.hashSamples = {};
      for (const hash of [0x2df95dfe, 0x5d9752f9, 0xec64918b, 0xa5023836]) {
        const pattern = Buffer.alloc(4);
        pattern.writeUInt32LE(hash);
        const at = bytes.indexOf(pattern);
        entry.hashSamples[hash.toString(16)] = at >= 0 ?
          { offset: at, context: bytes.subarray(Math.max(0, at - 16), at + 32).toString('hex') } : null;
      }
      if (process.argv.includes('--words')) {
        const at = entry.hashSamples['2df95dfe'].offset;
        entry.words = [];
        for (let pos = at - 96; pos < at + 128; pos += 4) {
          entry.words.push(`${pos - at}:0x${bytes.readUInt32LE(pos).toString(16)}`);
        }
      }
      found.push(entry);
    }
  }
  for (const bundle of opened.values()) bundle.close();
  for (const entry of found) console.log(entry);
  console.log(`Scanned ${packages.size} packages; ${found.length} network config entries`);
}

module.exports = { readBundlesIndex, readChunks, entriesOf, readPackageRange, gameData };
