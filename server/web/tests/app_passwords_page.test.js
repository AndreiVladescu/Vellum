// The console's app passwords page (v1.6.2).
//
// The property worth defending: a secret is on screen exactly once, in the
// dialog that made it, and never in the list. And the page tells someone what
// to type into the e-reader, since that is the whole reason they are here.
//
// Run with: node web/tests/app_passwords_page.test.js

const vm = require('node:vm');
const assert = require('node:assert');

const source = require('./console_source.js')();

function element(id) {
  const classes = new Set(id === 'page' ? ['hidden'] : []);
  return {
    id,
    innerHTML: '',
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
    value: '',
    textContent: '',
  };
}

function load(responses, answers = []) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const calls = [];
  const toasts = [];
  const asked = [];
  const sandbox = {
    document: {
      getElementById: get,
      querySelectorAll: (selector) =>
        selector === '#topbar .toolbar' ? [element('bar')] : [],
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
    location: { origin: 'https://books.example', hash: '' },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: {
      getItem: (k) => (k === 'vellum_email' ? 'reader@lib.test' : null),
      setItem: () => {},
      removeItem: () => {},
    },
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
  sandbox.api = (method, url, body) => {
    calls.push({ method, url, body });
    const key = method + ' ' + url;
    if (!(key in responses)) return Promise.reject(new Error('unexpected ' + key));
    return Promise.resolve(responses[key]);
  };
  sandbox.toast = (m) => toasts.push(m);
  // `ask()` waits for a click; answer it from the script instead.
  sandbox.ask = (opts) => {
    asked.push(opts);
    return Promise.resolve(answers.length ? answers.shift() : null);
  };
  return { sandbox, get, calls, toasts, asked };
}

let failures = 0;
const pending = [];
function check(name, fn) {
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

const LIST = [
  {
    id: 'a1', label: 'Kobo <Clara>', prefix: 'k3m9',
    created_at: '2026-11-01 10:00:00', last_used_at: '2026-11-12 21:15:03',
  },
  { id: 'a2', label: 'KOReader', prefix: 'x2qa', created_at: '2026-11-02 10:00:00', last_used_at: null },
];

check('the list names each device, never shows a secret, and says how to set one up', async () => {
  const { sandbox, get } = load({ 'GET /api/app-passwords': LIST });
  await sandbox.showAppPasswords();
  const html = get('page').innerHTML;

  assert.ok(html.includes('Kobo &lt;Clara&gt;'), 'labels are escaped');
  assert.ok(html.includes('k3m9-…'), 'identified by the prefix');
  assert.ok(html.includes('last used 2026-11-12 21:15'));
  assert.ok(html.includes('never used'));
  assert.ok(html.includes('data-act="revokeapppassword"'));
  assert.ok(html.includes('data-act="newapppassword"'));
  assert.ok(html.includes('https://books.example/opds'), 'the address to type in');
  assert.ok(html.includes('reader@lib.test'), 'and the username');
});

check('an empty list says what the page is for', async () => {
  const { sandbox, get } = load({ 'GET /api/app-passwords': [] });
  await sandbox.showAppPasswords();
  assert.ok(/No app passwords yet/.test(get('page').innerHTML));
});

check('a new one is shown once, with a way to copy it', async () => {
  const { sandbox, get, calls } = load(
    {
      'POST /api/app-passwords': {
        id: 'a3', label: 'Kindle', prefix: 'abcd', created_at: '2026-11-13 09:00:00',
        last_used_at: null, password: 'abcd-efgh-jkmn-pqrs-tvwx-yz01',
      },
      'GET /api/app-passwords': [],
    },
    [{ 0: 'Kindle' }],
  );
  await sandbox.newAppPassword();

  const post = calls.find((c) => c.method === 'POST');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(post.body)), { label: 'Kindle' });
  const modal = get('modal-root').innerHTML;
  assert.ok(modal.includes('abcd-efgh-jkmn-pqrs-tvwx-yz01'), 'the secret is shown');
  assert.ok(modal.includes('data-act="copysecret"'), 'with a copy button');
  assert.ok(/only time it is shown/.test(modal), 'and says it will not be again');

  // Done: the dialog goes, and the list it returns to has no secret in it.
  sandbox.appPasswordShown();
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(get('modal-root').innerHTML, '');
  assert.ok(!get('page').innerHTML.includes('abcd-efgh'), 'the list never carries it');
});

check('one made for KOReader asks for sync and says where to point it', async () => {
  const { sandbox, get, calls } = load(
    {
      'POST /api/app-passwords': {
        id: 'a4', label: 'KOReader', prefix: 'abcd', created_at: '2026-11-13 09:00:00',
        last_used_at: null, koreader: true, password: 'abcd-efgh-jkmn-pqrs-tvwx-yz01',
      },
      'GET /api/app-passwords': [],
    },
    [{ 0: 'KOReader', 1: 'koreader' }],
  );
  await sandbox.newAppPassword();
  const post = calls.find((c) => c.method === 'POST');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(post.body)), { label: 'KOReader', koreader: true });
  const modal = get('modal-root').innerHTML;
  assert.ok(modal.includes('https://books.example/koreader'), 'the sync server address');
  assert.ok(/exactly as shown/.test(modal), 'and that spelling matters for this one');
});

check('the list marks the ones that sync with KOReader', async () => {
  const { sandbox, get } = load({
    'GET /api/app-passwords': [{ ...LIST[1], koreader: true }, LIST[0]],
  });
  await sandbox.showAppPasswords();
  const html = get('page').innerHTML;
  assert.strictEqual((html.match(/KOReader sync<\/span>/g) || []).length, 1);
  assert.ok(html.includes('https://books.example/koreader'));
});

check('a nameless one is refused before any request', async () => {
  const { sandbox, calls, toasts } = load({}, [{ 0: '' }]);
  await sandbox.newAppPassword();
  assert.strictEqual(calls.length, 0);
  assert.ok(/name/.test(toasts.join(' ')));
});

check('cancelling the name dialog makes nothing', async () => {
  const { sandbox, calls } = load({}, [null]);
  await sandbox.newAppPassword();
  assert.strictEqual(calls.length, 0);
});

check('revoking asks first, then deletes and refreshes', async () => {
  const { sandbox, calls, asked } = load(
    { 'DELETE /api/app-passwords/a1': { ok: true }, 'GET /api/app-passwords': [] },
    [{}],
  );
  await sandbox.revokeAppPassword('a1', 'Kobo');
  assert.ok(asked[0].danger, 'a destructive confirmation');
  assert.ok(calls.some((c) => c.method === 'DELETE' && c.url === '/api/app-passwords/a1'));
  assert.ok(calls.some((c) => c.method === 'GET'), 'and the list is redrawn');
});

check('declining the revoke leaves it alone', async () => {
  const { sandbox, calls } = load({}, [null]);
  await sandbox.revokeAppPassword('a1', 'Kobo');
  assert.strictEqual(calls.length, 0);
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
