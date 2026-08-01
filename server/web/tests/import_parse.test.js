// The console importer's parsing, which is where import bugs actually live
// (next features #5).
//
// `console.js` is a browser script, so this loads it into a context with just
// enough of a DOM stub to let the declarations evaluate, then calls the pure
// functions. That is deliberately shallow — the *duplicate* rules are tested
// against the real server in `tests/import_check.rs`, because they live there.
//
// Run with: node web/tests/import_parse.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'console.js'),
  'utf8',
);

// console.js does run a little at load (a few `addEventListener` calls), so the
// stub covers those too. Values it returns are built inside this context, which
// is why the assertions below use `deepEqual` rather than `deepStrictEqual` —
// a cross-realm array has a different prototype and the strict form fails on
// that rather than on the contents.
const sandbox = {
  document: {
    getElementById: () => null,
    createElement: () => ({ classList: { toggle() {}, add() {} } }),
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

const { parseCatalogue, fromFilename, splitAuthors, parseCSV } = sandbox;

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

console.log('parseCSV');
check('handles quotes, escaped quotes and CRLF', () => {
  const rows = parseCSV('a,b\r\n"x,1","he said ""hi"""\r\n');
  assert.deepEqual(rows, [
    ['a', 'b'],
    ['x,1', 'he said "hi"'],
  ]);
});

console.log('parseCatalogue — CSV');
check('reads a plain catalogue', () => {
  const { items } = parseCatalogue('title,authors,year\nDune,Frank Herbert,1965');
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].title, 'Dune');
  assert.deepEqual(items[0].authors, ['Frank Herbert']);
  assert.strictEqual(items[0].published_year, 1965);
});

check('understands the aliases a real export uses', () => {
  // A Goodreads-shaped header, which is the whole point of having aliases.
  const { items } = parseCatalogue(
    'Book Title,Primary Author,Original Publication Year,ISBN/UID,Number of Pages\n' +
      'Piranesi,Susanna Clarke,2020,9781526622426,272',
  );
  assert.strictEqual(items[0].title, 'Piranesi');
  assert.deepEqual(items[0].authors, ['Susanna Clarke']);
  assert.strictEqual(items[0].published_year, 2020);
  assert.strictEqual(items[0].isbn, '9781526622426');
  assert.strictEqual(items[0].page_count, 272);
});

check('splits several authors', () => {
  assert.deepEqual(splitAuthors('Gaiman, Neil; Pratchett, Terry'), [
    'Gaiman',
    'Neil',
    'Pratchett',
    'Terry',
  ]);
  assert.deepEqual(splitAuthors('Neil Gaiman and Terry Pratchett'), [
    'Neil Gaiman',
    'Terry Pratchett',
  ]);
});

check('a missing title column is refused by name', () => {
  const r = parseCatalogue('author,year\nHomer,1996');
  assert.match(r.error, /title/);
});

check('rows without a title are skipped, not imported blank', () => {
  const { items } = parseCatalogue('title,year\n,1996\nSolaris,1961');
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].title, 'Solaris');
});

console.log('parseCatalogue — JSON');
check('reads a bare array', () => {
  const { items } = parseCatalogue(
    '[{"title":"Dune","authors":["Frank Herbert"],"year":1965}]',
  );
  assert.strictEqual(items[0].title, 'Dune');
  assert.strictEqual(items[0].published_year, 1965);
});

check('reads a {books:[...]} envelope', () => {
  const { items } = parseCatalogue('{"books":[{"title":"Solaris"}]}');
  assert.strictEqual(items[0].title, 'Solaris');
});

check('broken JSON says so instead of silently importing nothing', () => {
  const r = parseCatalogue('[{"title": ');
  assert.match(r.error, /not valid JSON/);
});

console.log('fromFilename');
check('reads Author - Title (Year)', () => {
  const m = fromFilename('Frank Herbert - Dune (1965).epub');
  assert.strictEqual(m.title, 'Dune');
  assert.deepEqual(m.authors, ['Frank Herbert']);
  assert.strictEqual(m.published_year, 1965);
});

check('falls back to the file name', () => {
  const m = fromFilename('some scanned thing.pdf');
  assert.strictEqual(m.title, 'some scanned thing');
  assert.deepEqual(m.authors, []);
  assert.strictEqual(m.published_year, null);
});

check('a title containing a dash is not mistaken for an author', () => {
  // The separator is " - " with spaces, so a hyphenated title survives.
  const m = fromFilename('Spider-Man.epub');
  assert.strictEqual(m.title, 'Spider-Man');
  assert.deepEqual(m.authors, []);
});

if (failures) {
  console.log('\n' + failures + ' failure(s)');
  process.exit(1);
}
console.log('\nall import parsing tests passed');
