// The console's ES modules, as the one classic script the tests have always run.
//
// The tests load the console into a `vm` context with a DOM stub and call its
// functions as globals (`sandbox.openPage(...)`, `vm.runInContext('S.token = …')`).
// That stays true after the split into `console/*.js`: this reads the modules in
// the order `console/main.js` imports them, drops the `import` lines and the
// `export` keywords, and joins them. A classic script's top-level functions are
// globals, which is the same thing main.js does for the browser by putting
// them on `window`; then it calls `start()`, as main.js does.
//
// `'use strict'` because modules are strict and the old script was not: a
// sloppy-only habit that slipped into a module should fail here, not in a
// browser.
//
// Imports must keep the shape the split gave them — `import { … } from '…';`,
// one statement, no side-effect-only imports — which is all this strips.

const fs = require('node:fs');
const path = require('node:path');

const dir = path.join(__dirname, '..', 'console');

/// The module files in load order, as main.js lists them.
function moduleFiles() {
  const main = fs.readFileSync(path.join(dir, 'main.js'), 'utf8');
  return [...main.matchAll(/^import\s[^;]*?from '\.\/([\w-]+\.js)';/gm)].map((m) => m[1]);
}

function strip(text) {
  return text
    .replace(/^import\s[^;]*;[ \t]*$/gm, '')
    .replace(/^export (?=(async function|function|const|let) )/gm, '');
}

function consoleSource() {
  const body = moduleFiles()
    .map((f) => `// ---- ${f}\n` + strip(fs.readFileSync(path.join(dir, f), 'utf8')))
    .join('\n');
  return `'use strict';\n${body}\nstart();\n`;
}

module.exports = consoleSource;
module.exports.moduleFiles = moduleFiles;
