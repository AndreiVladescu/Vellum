// What "Fetch metadata" does with edits you haven't saved.
//
// The server's enrich builds its search query from the *stored* title
// (`discover::enrich`), so a title trimmed on screen and not yet saved used to
// be looked up under its old name — the fix is that the panel writes what is on
// screen first. `pendingDetailEdits` is the part that decides, and it has to
// stay honest in both directions: send an edit, and send nothing when there is
// nothing to send (a needless PATCH bumps `updated_at`, which is the sync
// clock every other device pulls on).
//
// Run with: node web/tests/detail_edits.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

/// An input stub with the two values that matter: `defaultValue` is what the
/// row was rendered with, `value` is what is on screen now — the same pair a
/// real <input> exposes.
function field(initial) {
  return { defaultValue: initial, value: initial };
}

function load(fields) {
  const els = new Map(Object.entries(fields));
  const sandbox = {
    document: {
      getElementById: (id) => els.get(id) ?? null,
      createElement: () => ({ classList: { toggle() {}, add() {} }, remove() {} }),
      addEventListener: () => {},
      body: { appendChild: () => {} },
    },
    window: { addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener: () => {} }) },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: {},
    console,
    setTimeout,
    clearTimeout,
    URL,
    Blob: class {},
    addEventListener: () => {},
    matchMedia: () => ({ matches: false, addEventListener: () => {} }),
    requestAnimationFrame: () => {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  return sandbox;
}

const panel = (over = {}) => ({
  'd-title': field(over.title ?? 'Dune: Deluxe Anniversary Edition'),
  'd-subtitle': field(over.subtitle ?? ''),
  'd-year': field(over.year ?? '1965'),
  'd-desc': field(over.desc ?? 'A desert planet.'),
});

let failures = 0;
function check(name, fn) {
  try {
    fn();
    console.log('  ok   ' + name);
  } catch (e) {
    failures++;
    console.log('  FAIL ' + name + '\n       ' + e.message);
  }
}

console.log('pendingDetailEdits');

check('an untouched panel has nothing to save', () => {
  const s = load(panel());
  assert.strictEqual(s.pendingDetailEdits(), null);
});

check('a trimmed title is picked up — the reported bug', () => {
  const fields = panel();
  fields['d-title'].value = 'Dune';
  const s = load(fields);
  assert.deepEqual(s.pendingDetailEdits(), { title: 'Dune' });
});

check('only the fields that changed are sent', () => {
  const fields = panel();
  fields['d-title'].value = 'Dune';
  fields['d-year'].value = '1966';
  const s = load(fields);
  assert.deepEqual(s.pendingDetailEdits(), { title: 'Dune', published_year: 1966 });
});

check('whitespace either side of the same text is not an edit', () => {
  const fields = panel();
  fields['d-title'].value = '  Dune: Deluxe Anniversary Edition  ';
  const s = load(fields);
  assert.strictEqual(s.pendingDetailEdits(), null);
});

check('a description edit is compared untrimmed, so indentation counts', () => {
  const fields = panel();
  fields['d-desc'].value = 'A desert planet.\n\nWith worms.';
  const s = load(fields);
  assert.deepEqual(s.pendingDetailEdits(), { description: 'A desert planet.\n\nWith worms.' });
});

check('a year cleared to nothing sends no year rather than a NaN', () => {
  const fields = panel();
  fields['d-year'].value = '';
  const s = load(fields);
  assert.strictEqual(s.pendingDetailEdits(), null, 'nothing usable to send');
});

check('a title emptied is reported, so the caller can refuse it', () => {
  const fields = panel();
  fields['d-title'].value = '';
  const s = load(fields);
  assert.deepEqual(s.pendingDetailEdits(), { title: '' });
});

if (failures) {
  console.log(`\n${failures} failing`);
  process.exit(1);
}
console.log('\nall passed');
