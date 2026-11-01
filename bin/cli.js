#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

function resolveBinary(platformName = process.platform, architecture = process.arch) {
  const isWindows = platformName === 'win32';
  const binName = isWindows ? 'converto.exe' : 'converto';

  // Check locally compiled bundle
  if (!['arm64', 'x64'].includes(architecture)) return null;
  const arch = architecture;
  const platform = { darwin: 'macos', win32: 'windows', linux: 'linux' }[platformName];
  if (!platform) return null;
  const platformDir = `${platform}_${arch}`;

  const localBundle = path.join(__dirname, '..', 'build', 'cli', platformDir, 'bundle', 'bin', binName);
  if (fs.existsSync(localBundle)) {
    return localBundle;
  }

  return null;
}

function main() {
const binaryPath = resolveBinary();

if (!binaryPath) {
  console.error('[converto] Error: Precompiled native binary not found for this architecture.');
  console.error('[converto] Please visit https://converto.app/#downloads to install the standalone binary.');
  process.exit(1);
}

const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: 'inherit'
});

child.on('exit', (code) => {
  process.exit(code !== null ? code : 1);
});
child.on('error', (error) => {
  console.error(`[converto] Unable to start native CLI: ${error.message}`);
  process.exitCode = 1;
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => child.kill(signal));
}
}

module.exports = { resolveBinary };
if (require.main === module) main();

