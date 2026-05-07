#!/usr/bin/env node

const {
  OPTIONS_RULES_FOR_COPILOT,
  OPTIONS_RULES_FOR_COPILOT_STRICT,
  getOptionsMode,
  readStdinJson,
  appendLog
} = require('./copilot-config');

(function main() {
  const stdin = readStdinJson();
  const rawSize = (() => { try { return JSON.stringify(stdin).length; } catch (e) { return 0; } })();
  const keys = stdin && typeof stdin === 'object' ? Object.keys(stdin).join(',') : '';
  appendLog(`DEBUG sessionStart stdin keys=${keys} bytes=${rawSize}`);
  appendLog(`DEBUG sessionStart stdin raw=${JSON.stringify(stdin)}`);

  const mode = getOptionsMode();
  if (mode !== 'on' && mode !== 'strict') {
    process.stdout.write('{}');
    process.exit(0);
  }

  const rules = mode === 'strict' ? OPTIONS_RULES_FOR_COPILOT_STRICT : OPTIONS_RULES_FOR_COPILOT;
  const out = { additionalContext: rules };
  process.stdout.write(JSON.stringify(out));
  appendLog(`INFO sessionStart injected rules mode=${mode} len=${rules.length}`);
  process.exit(0);
})();
