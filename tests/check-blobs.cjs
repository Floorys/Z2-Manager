// Offline binary checks. Node is needed only by developers, not on the router.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const dir = path.join(__dirname, '..', 'fake');
const expected = {
  tls_clienthello_www_google_com: 'www.google.com',
  tls_clienthello_www_onetrust_com: 'www.onetrust.com',
  tls_clienthello_vk_com: 'vk.com',
  tls_clienthello_sberbank_ru: 'sberbank.ru',
  tls_clienthello_gosuslugi_ru: 'gosuslugi.ru',
  tls_clienthello_max_ru: 'max.ru',
};

function parseTls(b) {
  assert.equal(b[0], 22, 'TLS handshake record');
  assert.equal(b[5], 1, 'ClientHello');
  assert.equal(b.readUInt16BE(3), b.length - 5, 'record length');
  assert.equal(b.readUIntBE(6, 3), b.length - 9, 'handshake length');
  let p = 43;
  p += 1 + b[p];
  p += 2 + b.readUInt16BE(p);
  p += 1 + b[p];
  const extensionsLength = p;
  const end = p + 2 + b.readUInt16BE(p);
  assert.equal(end, b.length, 'extensions length');
  p += 2;
  let sni;
  while (p < end) {
    const type = b.readUInt16BE(p), size = b.readUInt16BE(p + 2);
    assert.ok(p + 4 + size <= end, 'extension bounds');
    if (type === 0) {
      assert.equal(b.readUInt16BE(p + 4), size - 2, 'SNI list length');
      assert.equal(b[p + 6], 0, 'host_name type');
      const length = b.readUInt16BE(p + 7);
      assert.equal(length + 5, size, 'SNI host length');
      sni = { offset: p, length, host: b.subarray(p + 9, p + 9 + length).toString('ascii') };
    }
    p += 4 + size;
  }
  assert.equal(p, end);
  assert.ok(sni, 'SNI extension present');
  return { ...sni, extensionsLength };
}

function rehost(b, hostname) {
  const info = parseTls(b), host = Buffer.from(hostname, 'ascii');
  const delta = host.length - info.length;
  const out = Buffer.concat([b.subarray(0, info.offset + 9), host, b.subarray(info.offset + 9 + info.length)]);
  out.writeUInt16BE(out.length - 5, 3);
  out.writeUIntBE(out.length - 9, 6, 3);
  out.writeUInt16BE(b.readUInt16BE(info.extensionsLength) + delta, info.extensionsLength);
  out.writeUInt16BE(host.length + 5, info.offset + 2);
  out.writeUInt16BE(host.length + 3, info.offset + 4);
  out.writeUInt16BE(host.length, info.offset + 7);
  assert.equal(parseTls(out).host, hostname);
  return out;
}

if (process.argv.includes('--repair')) {
  // SNI-adjusted bundled captures, not claims of captures from these services.
  for (const [name, host] of Object.entries(expected)) {
    const file = path.join(dir, `${name}.bin`);
    const b = fs.readFileSync(file);
    if (parseTls(b).host !== host) fs.writeFileSync(file, rehost(b, host));
  }
  const generic = path.join(dir, 'quic_initial_generic.bin');
  const original = path.join(dir, 'quic_initial_www_google_com.bin');
  if (!fs.existsSync(generic)) fs.copyFileSync(original, generic);
  for (const name of ['quic_initial_www_google_com.bin', 'quic_initial_vk_com.bin', 'quic_initial_4pda.to.bin', 'quic_initial_dbankcloud_ru.bin']) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) continue;
    assert.ok(fs.readFileSync(file).equals(fs.readFileSync(generic)), `not a known QUIC duplicate: ${name}`);
    fs.unlinkSync(file);
  }
}

const hashes = new Set();
for (const [name, host] of Object.entries(expected)) {
  const b = fs.readFileSync(path.join(dir, `${name}.bin`));
  assert.equal(parseTls(b).host, host, `${name}: SNI must match its label`);
  const hash = crypto.createHash('sha256').update(b).digest('hex');
  assert.ok(!hashes.has(hash), `${name}: duplicate labeled ClientHello`);
  hashes.add(hash);
  console.log(`ok - ${name}: ${host}`);
}
const quicFiles = fs.readdirSync(dir).filter(f => f.startsWith('quic_initial_'));
assert.deepEqual(quicFiles, ['quic_initial_generic.bin'], 'one honestly labeled generic QUIC capture');
const quic = fs.readFileSync(path.join(dir, quicFiles[0]));
assert.ok(quic.length >= 1200 && (quic[0] & 0xc0) === 0xc0, 'QUIC long-header Initial');
console.log('ok - one generic QUIC Initial, no fictitious domain variants');
