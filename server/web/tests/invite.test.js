// Inviting somebody from the console.
//
// Two reports drove this. The link came back through `prompt()` — a browser
// dialog with a URL crammed into a text box and "OK / Cancel" on something
// that cannot be cancelled, since the invitation is already made. And people
// were typing the name they know somebody by into the field that wanted an
// email address, because nothing said which was which.
//
// The third thing here is the 401 handling: the console used to sign you out
// on *any* 401, which throws away whatever you were in the middle of. It now
// asks whether the session is actually dead first.
//
// Run with: node web/tests/invite.test.js

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
    select() {},
    getBoundingClientRect: () => ({ height: 0, width: 0, top: 0, left: 0 }),
    querySelector: () => element('inner'),
    querySelectorAll: () => [],
    appendChild() {},
    addEventListener() {},
    textContent: '',
  };
}

function load({ responses = {}, fields = {}, fail = () => null, fetchImpl,
               realApi = false } = {}) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id, fields[id] ?? ''));
    return els.get(id);
  };
  const calls = [];
  const toasts = [];
  const prompts = [];
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
    localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: fetchImpl || (() => Promise.reject(new Error('no network in this test'))),
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
  // The 401 tests exercise the real `api()`; everything else stubs it out.
  if (!realApi) sandbox.api = (method, url, body) => {
    calls.push({ method, url, body });
    const failure = fail(body);
    if (failure) return Promise.reject(new Error(failure));
    const key = method + ' ' + url;
    return Promise.resolve(key in responses ? responses[key] : {});
  };
  sandbox.toast = (m) => toasts.push(m);
  sandbox.prompt = (...args) => {
    prompts.push(args);
    return null;
  };
  return { sandbox, calls, toasts, prompts, get };
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

// `invitePerson()` refreshes the People screen when it is done, so every
// invite test needs those two lists to exist.
const PEOPLE = { 'GET /api/users': [], 'GET /api/invites': [] };

console.log('Inviting');

check('a username in the address field is refused before any request', async () => {
  const { sandbox, calls, toasts } = load({
    fields: { 'inv-email': 'teodor', 'inv-name': '' },
  });
  await sandbox.invitePerson();

  assert.strictEqual(calls.length, 0, 'nothing was sent');
  const said = toasts.join(' ');
  assert.ok(/looks like a name/.test(said), `should name the mistake: ${said}`);
  assert.ok(/Name field/i.test(said), `and where it belongs: ${said}`);
});

check('an empty address says so plainly', async () => {
  const { sandbox, calls, toasts } = load({ fields: { 'inv-email': '  ' } });
  await sandbox.invitePerson();
  assert.strictEqual(calls.length, 0);
  assert.ok(/email address is needed/.test(toasts.join(' ')));
});

check('the name is sent alongside the address, not instead of it', async () => {
  const { sandbox, calls } = load({
    fields: { 'inv-email': 'teodor@lib.test', 'inv-name': 'Teodor' },
    responses: { ...PEOPLE, 'POST /api/invites': { email: 'teodor@lib.test' } },
  });
  await sandbox.invitePerson();

  const post = calls.find((c) => c.method === 'POST');
  assert.strictEqual(post.body.email, 'teodor@lib.test');
  assert.strictEqual(post.body.display_name, 'Teodor');
});

check('no name is sent when none was given', async () => {
  const { sandbox, calls } = load({
    fields: { 'inv-email': 'teodor@lib.test', 'inv-name': '' },
    responses: { ...PEOPLE, 'POST /api/invites': { email: 'teodor@lib.test' } },
  });
  await sandbox.invitePerson();
  const post = calls.find((c) => c.method === 'POST');
  assert.strictEqual(post.body.display_name, undefined);
});

check('the link is shown in a dialog, never through prompt()', async () => {
  const { sandbox, prompts, get } = load({
    fields: { 'inv-email': 'ana@lib.test', 'inv-name': 'Ana' },
    responses: {
      ...PEOPLE,
      'POST /api/invites': {
        email: 'ana@lib.test',
        url: 'http://vellum.local/join/abc123',
        expires_at: '2026-08-25 10:00:00',
      },
    },
  });
  await sandbox.invitePerson();

  assert.strictEqual(prompts.length, 0, 'prompt() is what this replaced');
  const html = get('modal-root').innerHTML;
  assert.ok(html.includes('http://vellum.local/join/abc123'), 'the link is there');
  assert.ok(html.includes('Ana'), 'and who it is for');
  assert.ok(html.includes('2026-08-25'), 'and when it stops working');
  assert.ok(html.includes('data-act="copyurl"'), 'with a way to copy it');
  assert.ok(/no email set up/.test(html), 'and why it is being handed over');
});

check('an emailed invitation shows the link too, and says it was sent', async () => {
  // Withholding it once the mail went out made an invitation lost to a spam
  // folder unrecoverable — the only way back was to withdraw and start again.
  const { sandbox, get } = load({
    fields: { 'inv-email': 'ana@lib.test', 'inv-name': 'Ana' },
    responses: {
      ...PEOPLE,
      'POST /api/invites': {
        email: 'ana@lib.test',
        emailed: true,
        url: 'http://vellum.local/join/abc123',
        expires_at: '2026-08-25 10:00:00',
      },
    },
  });
  await sandbox.invitePerson();

  const html = get('modal-root').innerHTML;
  assert.ok(html.includes('http://vellum.local/join/abc123'), 'the link is still there');
  assert.ok(/Emailed to/.test(html), 'and says it went out');
  assert.ok(html.includes('ana@lib.test'), 'naming where it went');
  assert.ok(!/no email set up/.test(html), 'not the mail-is-off wording');
});

console.log('\nA 401 that is not the end of your session');

check('a live session survives one unauthorised request', async () => {
  // The reported symptom: signed out mid-task. Only `/api/auth/me` decides.
  let loggedOut = false;
  const { sandbox } = load({
    realApi: true,
    fetchImpl: (url) =>
      Promise.resolve(
        String(url).includes('/api/auth/me')
          ? { status: 200, json: () => Promise.resolve({ id: 'u1' }) }
          : { status: 401, json: () => Promise.resolve({ error: 'nope' }) },
      ),
  });
  vm.runInContext('S.token = "t"', sandbox);
  sandbox.logout = () => { loggedOut = true; };

  await assert.rejects(
    () => sandbox.api('POST', '/api/invites', {}),
    /not authorised|nope/,
  );
  assert.strictEqual(loggedOut, false, 'the session was fine');
});

check('a dead session still signs you out', async () => {
  let loggedOut = false;
  const { sandbox } = load({
    realApi: true,
    fetchImpl: () =>
      Promise.resolve({ status: 401, json: () => Promise.resolve({}) }),
  });
  vm.runInContext('S.token = "t"', sandbox);
  sandbox.logout = () => { loggedOut = true; };

  await assert.rejects(() => sandbox.api('GET', '/api/users'), /Session expired/);
  assert.strictEqual(loggedOut, true);
});

check('a network failure while checking is not treated as expiry', async () => {
  // Being signed out because the wifi dropped is the thing this prevents.
  let loggedOut = false;
  const { sandbox } = load({
    realApi: true,
    fetchImpl: (url) =>
      String(url).includes('/api/auth/me')
        ? Promise.reject(new Error('offline'))
        : Promise.resolve({ status: 401, json: () => Promise.resolve({}) }),
  });
  vm.runInContext('S.token = "t"', sandbox);
  sandbox.logout = () => { loggedOut = true; };

  await assert.rejects(() => sandbox.api('GET', '/api/users'));
  assert.strictEqual(loggedOut, false);
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
