// Covers and downloads use short-lived signed links (v1.6.2): the session token
// rides a header to POST /api/links and never appears in an image or download
// URL, and anything that can't be signed falls back to a header-authenticated
// blob fetch.
//
// Run with: node web/tests/signed_links.test.js

const vm = require('node:vm');
const assert = require('node:assert');
const { test } = require('node:test');

const source = require('./console_source.js')();

function img(src) {
  return {
    src: '',
    attrs: { 'data-src': src },
    getAttribute(k) { return this.attrs[k]; },
    removeAttribute(k) { delete this.attrs[k]; },
    addEventListener() {},
  };
}

function load(inner) {
  // start() asks the server about registration; keep that out of the call logs.
  const fetchImpl = (url, opts) => (url === '/api/auth/registration'
    ? Promise.resolve({ ok: true, status: 200, json: async () => ({}) }) : inner(url, opts));
  const el = () => ({
    classList: { add() {}, remove() {}, contains: () => false, toggle() {} },
    querySelector: () => el(), querySelectorAll: () => [], appendChild() {},
    addEventListener() {}, getBoundingClientRect: () => ({}), style: {},
  });
  const clicked = [];
  const sandbox = {
    document: {
      getElementById: el,
      querySelectorAll: () => [],
      createElement: () => ({ click() { clicked.push(this); }, remove() {}, setAttribute() {} }),
      addEventListener() {},
      body: { appendChild() {} },
      documentElement: { style: { setProperty() {} } },
    },
    window: { addEventListener() {}, matchMedia: () => ({ matches: false, addEventListener() {} }), scrollTo() {} },
    location: { origin: 'https://b.example', hash: '' },
    localStorage: { getItem: () => null, setItem() {} },
    sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    fetch: fetchImpl, crypto: {}, console, setTimeout, clearTimeout,
    URL: { createObjectURL: () => 'blob:fallback', revokeObjectURL() {} },
    Blob: class {}, Promise, addEventListener() {},
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    requestAnimationFrame() {}, scrollTo() {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  vm.runInContext("S.token = 'SESSION'", sandbox);
  return { sandbox, clicked };
}

const tick = () => new Promise((r) => setTimeout(r, 10));

test('covers use one signed batch and keep their query after the signature', async () => {
  const calls = [];
  const { sandbox } = load(async (url, opts) => {
    calls.push({ url, opts });
    const paths = JSON.parse(opts.body).paths;
    return {
      ok: true, status: 200,
      json: async () => ({
        links: paths.map((p) => ({
          path: p, url: p + '?u=U&exp=9&sig=abc', expires_at: Date.now() / 1000 + 21600,
        })),
      }),
    };
  });
  const a = img('/api/books/1/cover?w=80'), b = img('/api/books/2/cover?t=5');
  const root = { querySelectorAll: () => [a, b] };
  sandbox.hydrateImages(root);
  await tick();

  assert.strictEqual(calls.length, 1, 'one request signs every cover');
  assert.strictEqual(calls[0].opts.headers.authorization, 'Bearer SESSION');
  assert.strictEqual(a.src, '/api/books/1/cover?u=U&exp=9&sig=abc&w=80');
  assert.strictEqual(b.src, '/api/books/2/cover?u=U&exp=9&sig=abc&t=5');
  assert.ok(!a.src.includes('SESSION') && !b.src.includes('SESSION'));

  // A second render reuses the cached links.
  sandbox.hydrateImages({ querySelectorAll: () => [img('/api/books/1/cover?w=80')] });
  await tick();
  assert.strictEqual(calls.length, 1, 'cached until near expiry');
});

test('a cover that cannot be signed falls back to an authorised blob fetch', async () => {
  const calls = [];
  const { sandbox } = load(async (url, opts) => {
    calls.push(url);
    if (url === '/api/links') return { ok: true, status: 200, json: async () => ({ links: [] }) };
    return { ok: true, status: 200, blob: async () => ({}) };
  });
  const a = img('/api/books/9/cover');
  sandbox.hydrateImages({ querySelectorAll: () => [a] });
  await tick();
  assert.deepStrictEqual(calls, ['/api/links', '/api/books/9/cover']);
  assert.strictEqual(a.src, 'blob:fallback');
});

test('a download follows a signed link instead of buffering a blob', async () => {
  const { sandbox, clicked } = load(async () => ({
    ok: true, status: 200,
    json: async () => ({
      links: [{ path: '/api/files/f1', url: '/api/files/f1?u=U&exp=9&sig=abc', expires_at: Date.now() / 1000 + 300 }],
    }),
  }));
  assert.strictEqual(await sandbox.downloadFile('f1', 'dune.pdf'), true);
  assert.strictEqual(clicked.length, 1);
  assert.strictEqual(clicked[0].href, '/api/files/f1?u=U&exp=9&sig=abc');
  assert.strictEqual(clicked[0].download, 'dune.pdf');
});
