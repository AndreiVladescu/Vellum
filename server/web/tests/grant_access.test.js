// Giving someone access from the console.
//
// The API has always been able to share a single book, a tag, or the whole
// library, at read or read-and-write. The console could only ever *revoke*, so
// the one way to give somebody write access was an invitation — which is
// all-or-nothing, and is how a "read/write member" ended up able to see
// everything and change nothing in particular.
//
// The case worth pinning is the tick-list: it becomes one share per book, and a
// partial failure has to be reported as partial. "Granted" when two of nine
// failed is the sort of thing nobody notices until someone cannot open a book.
//
// Run with: node web/tests/grant_access.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

function element(id, value = '') {
  const classes = new Set(id === 'page' ? ['hidden'] : []);
  return {
    id,
    innerHTML: '',
    value,
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c),
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
    },
    hidden: () => classes.has('hidden'),
    remove() {},
    focus() {},
    getBoundingClientRect: () => ({ height: 0, width: 0, top: 0, left: 0 }),
    querySelector: () => element('inner'),
    querySelectorAll: () => [],
    appendChild() {},
    addEventListener() {},
    textContent: '',
  };
}

function load({ responses = {}, fields = {}, fail = () => false } = {}) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id, fields[id] ?? ''));
    return els.get(id);
  };
  const calls = [];
  const toasts = [];
  const sandbox = {
    document: {
      getElementById: get,
      querySelectorAll: (s) => (s === '#topbar .toolbar' ? [element('bar')] : []),
      createElement: () => element('made'),
      addEventListener: () => {},
      body: { appendChild: () => {} },
      documentElement: { style: { setProperty: () => {} } },
    },
    window: {
      addEventListener: () => {},
      matchMedia: () => ({ matches: false, addEventListener: () => {} }),
      scrollTo: () => {},
    },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: {},
    console,
    setTimeout,
    clearTimeout,
    URL,
    Blob: class {},
    Promise,
    addEventListener: () => {},
    matchMedia: () => ({ matches: false, addEventListener: () => {} }),
    requestAnimationFrame: () => {},
    scrollTo: () => {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  // `S` is declared with `const`, so it never lands on the sandbox object the
  // way a function declaration does. Reaching it means running code inside.
  const select = (ids) =>
    vm.runInContext(`S.selected = new Set(${JSON.stringify(ids)})`, sandbox);
  sandbox.api = (method, url, body) => {
    calls.push({ method, url, body });
    const failure = fail(body);
    if (failure) return Promise.reject(new Error(failure));
    const key = method + ' ' + url;
    return Promise.resolve(key in responses ? responses[key] : {});
  };
  sandbox.toast = (m) => toasts.push(m);
  return { sandbox, calls, toasts, get, select };
}

let failures = 0;
const pending = [];
function check(name, fn) {
  // A test that never settles used to exit the runner silently with status 0:
  // `Promise.all` never fired, the event loop drained, and the missing lines
  // were the only clue. A dialog that waits for a click nobody makes is
  // exactly that shape, so time out and fail loudly instead.
  let timer;
  const guard = new Promise((_, reject) => {
    timer = setTimeout(
      () => reject(new Error('timed out — did something wait for a click?')),
      5000,
    );
  });
  pending.push(
    Promise.race([Promise.resolve().then(fn), guard])
      .then(() => console.log('  ok   ' + name))
      .catch((e) => {
        failures++;
        console.log('  FAIL ' + name + '\n       ' + e.message);
      })
      .finally(() => clearTimeout(timer)),
  );
}

const SHARES_PAGE = {
  'GET /api/shares': [],
  'GET /api/share-links': [],
  'GET /api/users': [{ email: 'ana@lib.test' }],
};

console.log('Granting access');

check('the whole library is one share', async () => {
  const { sandbox, calls } = load({
    responses: SHARES_PAGE,
    fields: { 'g-email': 'ana@lib.test', 'g-scope': 'all', 'g-perm': 'editor' },
  });
  await sandbox.grantAccess();

  const post = calls.find((c) => c.method === 'POST');
  // Field by field: objects made inside the VM have that context's prototype,
  // so `deepStrictEqual` against a literal from out here never matches.
  assert.strictEqual(post.body.grantee_email, 'ana@lib.test');
  assert.strictEqual(post.body.permission, 'editor');
  assert.strictEqual(post.body.scope, 'all');
  assert.strictEqual(post.body.scope_id, undefined, 'nothing narrows it');
});

check('a tag shares the group, by id', async () => {
  const { sandbox, calls } = load({
    responses: SHARES_PAGE,
    fields: { 'g-email': 'ana@lib.test', 'g-scope': 'group:g7', 'g-perm': 'viewer' },
  });
  await sandbox.grantAccess();

  const post = calls.find((c) => c.method === 'POST');
  assert.strictEqual(post.body.scope, 'group');
  assert.strictEqual(post.body.scope_id, 'g7');
  assert.strictEqual(post.body.permission, 'viewer');
});

check('a tick-list becomes one share per book', async () => {
  const { sandbox, calls, select } = load({
    responses: SHARES_PAGE,
    fields: { 'g-email': 'ana@lib.test', 'g-scope': 'selected', 'g-perm': 'editor' },
  });
  select(['b1', 'b2', 'b3']);
  await sandbox.grantAccess();

  const posts = calls.filter((c) => c.method === 'POST');
  assert.strictEqual(posts.length, 3);
  assert.deepStrictEqual(
    posts.map((p) => p.body.scope_id).sort(),
    ['b1', 'b2', 'b3'],
  );
  assert.ok(posts.every((p) => p.body.scope === 'book'));
});

check('a partial failure is reported as partial', async () => {
  const { sandbox, toasts, select } = load({
    responses: SHARES_PAGE,
    fields: { 'g-email': 'ana@lib.test', 'g-scope': 'selected', 'g-perm': 'editor' },
    fail: (body) => (body && body.scope_id === 'b2' ? 'you do not own this book' : null),
  });
  select(['b1', 'b2', 'b3']);
  await sandbox.grantAccess();

  const said = toasts.join(' | ');
  assert.ok(/2 of 3/.test(said), `should count what worked: ${said}`);
  assert.ok(/do not own/.test(said), `and say why the rest did not: ${said}`);
});

check('no email grants nothing', async () => {
  const { sandbox, calls, toasts } = load({
    responses: SHARES_PAGE,
    fields: { 'g-email': '   ', 'g-scope': 'all', 'g-perm': 'viewer' },
  });
  await sandbox.grantAccess();

  assert.strictEqual(
    calls.filter((c) => c.method === 'POST').length,
    0,
    'nothing was sent',
  );
  assert.ok(/who/i.test(toasts.join(' ')), 'and it says what is missing');
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
