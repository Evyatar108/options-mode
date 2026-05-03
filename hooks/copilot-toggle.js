#!/usr/bin/env node

const fs = require('fs');
const { VALID_MODES, getFlagPath, readFlag, safeWriteFlag } = require('./copilot-config');

function usage() {
  return 'usage: node copilot-toggle.js on|off|status';
}

(function main() {
  const arg = (process.argv[2] || 'status').toLowerCase();

  if (arg === 'status') {
    const mode = readFlag();
    if (mode === null) {
      process.stdout.write('options mode (copilot): off (no flag set)\n');
    } else {
      process.stdout.write(`options mode (copilot): ${mode}\n`);
    }
    process.exit(0);
  }

  if (!VALID_MODES.includes(arg)) {
    process.stderr.write(usage() + '\n');
    process.exit(1);
  }

  safeWriteFlag(arg);
  const verify = readFlag();
  if (verify !== arg) {
    process.stderr.write(`options mode (copilot): write failed (read back ${verify}). flag path: ${getFlagPath()}\n`);
    process.exit(2);
  }
  process.stdout.write(`options mode (copilot): ${arg}\n`);
  process.exit(0);
})();
