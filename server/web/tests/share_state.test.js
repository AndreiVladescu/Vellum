// How the Shares screen decides whether a link is still open.
//
// The four states come from three different columns and a clock, and getting
// one wrong is the kind of bug that tells someone a link is closed when anyone
// holding the URL can still download the book. The server's own `LINK_VALID`
// is the authority; this is the console agreeing with it.
//
// Run with: node web/tests/share_state.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

const sandbox = {
  document: {
    getElementById: () => null,
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

const { linkState } = sandbox;

/// The server writes timestamps as UTC "YYYY-MM-DD HH:MM:SS", with no zone
/// marker — the shape the console has to read back.
const stamp = (offsetMs) =>
  new Date(Date.now() + offsetMs).toISOString().slice(0, 19).replace('T', ' ');

const link = (over) => ({
  revoked: false,
  expires_at: null,
  max_uses: null,
  use_count: 0,
  ...over,
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

console.log('linkState');

check('a plain link is live', () => {
  assert.strictEqual(linkState(link({})).label, 'Live');
});

check('revoked beats everything else', () => {
  assert.strictEqual(
    linkState(link({ revoked: true, expires_at: stamp(60_000) })).label,
    'Revoked',
  );
});

check('an expiry in the past is Expired', () => {
  assert.strictEqual(linkState(link({ expires_at: stamp(-60_000) })).label, 'Expired');
});

check('an expiry in the future is still Live', () => {
  assert.strictEqual(linkState(link({ expires_at: stamp(3_600_000) })).label, 'Live');
});

check('a used-up one-time link is closed', () => {
  assert.strictEqual(linkState(link({ max_uses: 1, use_count: 1 })).label, 'Used up');
});

check('a one-time link nobody has used is live', () => {
  assert.strictEqual(linkState(link({ max_uses: 1, use_count: 0 })).label, 'Live');
});

check('unlimited uses never counts as used up', () => {
  assert.strictEqual(linkState(link({ max_uses: null, use_count: 99 })).label, 'Live');
});

check('only Live is styled as open', () => {
  assert.strictEqual(linkState(link({})).cls, 'on');
  assert.strictEqual(linkState(link({ revoked: true })).cls, 'off');
});

if (failures) {
  console.log(`\n${failures} failing`);
  process.exit(1);
}
console.log('\nall passed');
