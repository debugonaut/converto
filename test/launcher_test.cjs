const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { resolveBinary } = require('../bin/cli.js');

test('launcher maps the exact OS and architecture without a foreign fallback', () => {
  const exists = fs.existsSync;
  const seen = [];
  fs.existsSync = (p) => { seen.push(p); return true; };
  try {
    assert.match(resolveBinary('win32', 'x64'), /windows_x64.*converto\.exe$/);
    assert.match(resolveBinary('darwin', 'arm64'), /macos_arm64.*converto$/);
    assert.match(resolveBinary('linux', 'x64'), /linux_x64.*converto$/);
    assert.equal(resolveBinary('linux', 'ia32'), null);
    assert.equal(resolveBinary('unknown', 'x64'), null);
    fs.existsSync = () => false;
    assert.equal(resolveBinary('linux', 'arm64'), null);
    assert.equal(seen.length, 3);
  } finally { fs.existsSync = exists; }
});
