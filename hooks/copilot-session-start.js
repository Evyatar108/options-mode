#!/usr/bin/env node

const { OPTIONS_RULES_FOR_COPILOT, isOptionsActive, readStdinJson, appendLog } = require('./copilot-config');

(function main() {
  readStdinJson();

  if (!isOptionsActive()) {
    process.stdout.write('{}');
    process.exit(0);
  }

  const out = { additionalContext: OPTIONS_RULES_FOR_COPILOT };
  process.stdout.write(JSON.stringify(out));
  appendLog(`INFO sessionStart injected rules len=${OPTIONS_RULES_FOR_COPILOT.length}`);
  process.exit(0);
})();
