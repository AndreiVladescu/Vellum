// The console's two-factor pieces (v1.6.2): the Account security page, the
// second sign-in step, and an owner's "Clear 2FA" on People.
//
// What is worth defending: the password goes first and the code is a separate
// step carrying only the challenge; recovery codes appear once, in a dialog;
// the QR code is shown through a data: URL, never as markup; and turning it
// off sends whichever proof was typed.
//
// Run with: node web/tests/security_page.test.js

const vm = require('node:vm');
const assert = require('node:assert');

const source = require('./console_source.js')();

function element(id) {
  const classes = new Set(['page', 'l-2fa'].includes(id) ? ['hidden'] : []);
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
    select() {},
    getBoundingClientRect: () => ({ height: 0, width: 0, top: 0, left: 0 }),
    querySelector: () => element('inner'),
    querySelectorAll: () => [],
    appendChild() {},
    addEventListener() {},
    value: '',
    textContent: '',
  };
}

/// `responses` maps "METHOD url" to a value, or to a function of the body
/// (which may throw, to answer with an error).
function load(responses, answers = [], fetches = []) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const calls = [];
  const toasts = [];
  const asked = [];
  const fetched = [];
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
      getItem: (k) => (k === 'vellum_email' ? 'owner@lib.test' : null),
      setItem: () => {},
      removeItem: () => {},
    },
    // Only the sign-in calls go through fetch directly; everything else is
    // `api()`, stubbed below.
    fetch: (url, opts) => {
      // Boot asks other things (whether registration is open); those get no
      // network, and must not eat the sign-in answers queued for the test.
      if (!String(url).startsWith('/api/auth/login')) {
        return Promise.reject(new Error('no network in this test'));
      }
      fetched.push({ url, body: opts && opts.body ? JSON.parse(opts.body) : null });
      const next = fetches.shift();
      if (!next) return Promise.reject(new Error('unexpected fetch ' + url));
      return Promise.resolve({
        ok: next.status >= 200 && next.status < 300,
        status: next.status,
        json: () => Promise.resolve(next.body),
      });
    },
    crypto: {},
    console,
    setTimeout,
    clearTimeout,
    URL,
    btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
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
    calls.push({ method, url, body: body && JSON.parse(JSON.stringify(body)) });
    const key = method + ' ' + url;
    if (!(key in responses)) return Promise.reject(new Error('unexpected ' + key));
    try {
      const r = responses[key];
      return Promise.resolve(typeof r === 'function' ? r(body) : r);
    } catch (e) {
      return Promise.reject(e);
    }
  };
  sandbox.toast = (m) => toasts.push(m);
  sandbox.ask = (opts) => {
    asked.push(opts);
    return Promise.resolve(answers.length ? answers.shift() : null);
  };
  let shown = 0;
  sandbox.showApp = () => { shown++; };
  return { sandbox, get, calls, toasts, asked, fetched, shownApp: () => shown };
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

const OFF = { enabled: false, enabled_at: null, recovery_codes_left: 0 };
const ON = { enabled: true, enabled_at: '2026-11-13 09:41:07', recovery_codes_left: 2 };
const CODES = ['abcd-efgh-jkmn-pqrs', '0123-4567-89ab-cdef'];

check('off: the page offers to set it up and explains e-readers', async () => {
  const { sandbox, get } = load({ 'GET /api/auth/2fa': OFF });
  await sandbox.showSecurity();
  const html = get('page').innerHTML;
  assert.ok(html.includes('data-act="setup2fa"'));
  assert.ok(!html.includes('data-act="disable2fa"'));
  assert.ok(/app passwords/.test(html), 'says what happens to e-readers');
});

check('on: says since when, warns when recovery codes run low', async () => {
  const { sandbox, get } = load({ 'GET /api/auth/2fa': ON });
  await sandbox.showSecurity();
  const html = get('page').innerHTML;
  assert.ok(html.includes('2026-11-13'));
  assert.ok(html.includes('2 of 10 recovery codes left'));
  assert.ok(/make new ones/.test(html), 'a warning at two left');
  assert.ok(html.includes('data-act="regen2fa"'));
  assert.ok(html.includes('data-act="disable2fa"'));
  assert.ok(!html.includes('data-act="setup2fa"'));
});

check('an older server says so instead of failing', async () => {
  const { sandbox, get } = load({
    'GET /api/auth/2fa': () => { const e = new Error('not found'); e.status = 404; throw e; },
  });
  await sandbox.showSecurity();
  assert.ok(/too old/.test(get('page').innerHTML));
});

check('setting up: password, then the QR as an image, a code, then the codes once', async () => {
  let tries = 0;
  const { sandbox, get, calls, asked } = load(
    {
      'POST /api/auth/2fa/setup': {
        secret: 'JBSW Y3DP EHPK 3PXP',
        otpauth_uri: 'otpauth://totp/Vellum:owner%40lib.test?secret=JBSWY3DPEHPK3PXP',
        qr_svg: '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1v1H0V0"/></svg>',
      },
      'POST /api/auth/2fa/enable': () => {
        tries++;
        if (tries === 1) throw new Error("that code doesn't match");
        return { recovery_codes: CODES };
      },
      'GET /api/auth/2fa': ON,
    },
    [{ 0: 'my password' }, { 0: '000000' }, { 0: '123456' }],
  );
  await sandbox.setup2fa();

  assert.deepStrictEqual(calls[0], {
    method: 'POST', url: '/api/auth/2fa/setup', body: { password: 'my password' },
  });
  assert.strictEqual(asked[0].fields[0].type, 'password');

  const qr = asked[1].html;
  assert.ok(qr.includes('src="data:image/svg+xml;base64,'), 'the QR is an image');
  assert.ok(!qr.includes('<svg'), 'never inlined as markup');
  assert.ok(qr.includes('JBSW Y3DP EHPK 3PXP'), 'and the key to type by hand');

  // A wrong code asks again, with the reason, against the same secret.
  assert.ok(asked[2].html.includes('doesn'), 'the reason is shown');
  assert.strictEqual(calls.filter((c) => c.url === '/api/auth/2fa/setup').length, 1);
  const enables = calls.filter((c) => c.url === '/api/auth/2fa/enable');
  assert.deepStrictEqual(enables.map((c) => c.body.code), ['000000', '123456']);

  const modal = get('modal-root').innerHTML;
  for (const c of CODES) assert.ok(modal.includes(c), 'every recovery code is shown');
  assert.ok(/only time they are\s+shown/.test(modal));

  sandbox.recoveryCodesShown();
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(get('modal-root').innerHTML, '');
  assert.ok(!get('page').innerHTML.includes(CODES[0]), 'the page never carries them');
});

check('setting up without a password asks nothing of the server', async () => {
  const { sandbox, calls } = load({}, [{ 0: '' }]);
  await sandbox.setup2fa();
  assert.strictEqual(calls.length, 0);
});

check('turning it off sends a code as a code and a password as a password', async () => {
  assert.deepStrictEqual({ ...load({}).sandbox.securityProof('123 456') }, { code: '123 456' });
  assert.deepStrictEqual(
    { ...load({}).sandbox.securityProof('ABCD-EFGH-JKMN-PQRS') },
    { code: 'ABCD-EFGH-JKMN-PQRS' },
  );
  assert.deepStrictEqual(
    { ...load({}).sandbox.securityProof('a long enough passphrase') },
    { password: 'a long enough passphrase' },
  );

  const { sandbox, calls, asked } = load(
    { 'POST /api/auth/2fa/disable': { ok: true }, 'GET /api/auth/2fa': OFF },
    [{ 0: '654321' }],
  );
  await sandbox.disable2fa();
  assert.ok(asked[0].danger);
  assert.deepStrictEqual(calls[0].body, { code: '654321' });
});

check('new recovery codes need proof and are shown once', async () => {
  const { sandbox, get, calls } = load(
    { 'POST /api/auth/2fa/recovery-codes': { recovery_codes: CODES } },
    [{ 0: 'a long enough passphrase' }],
  );
  await sandbox.regen2fa();
  assert.deepStrictEqual(calls[0].body, { password: 'a long enough passphrase' });
  assert.ok(/old ones no longer work/.test(get('modal-root').innerHTML));
});

check('sign-in: a right password on a 2FA account asks for the code next', async () => {
  const { sandbox, get, fetched, shownApp } = load({}, [], [
    { status: 401, body: { error: 'two-factor', two_factor_required: true, challenge: 'ch1' } },
    { status: 200, body: { token: 'tok', user: { email: 'owner@lib.test', is_master: true } } },
  ]);
  get('l-email').value = 'owner@lib.test';
  get('l-pass').value = 'pw';
  await sandbox.login();

  assert.strictEqual(shownApp(), 0, 'not signed in yet');
  assert.ok(get('l-form').hidden(), 'the password form makes way');
  assert.ok(!get('l-2fa').hidden(), 'for the code form');
  assert.strictEqual(get('l-pass').value, '', 'and the password is not left in the page');
  assert.strictEqual(get('l-err').textContent, '');

  get('l-code').value = ' 123456 ';
  await sandbox.loginCode();
  assert.deepStrictEqual(fetched[1], {
    url: '/api/auth/login/2fa', body: { challenge: 'ch1', code: '123456' },
  });
  assert.strictEqual(shownApp(), 1);
  assert.strictEqual(vm.runInContext('S.token', sandbox), 'tok');
  assert.ok(get('l-2fa').hidden());
});

check('sign-in: a wrong code says so; a dead challenge goes back to the password', async () => {
  const { sandbox, get } = load({}, [], [
    { status: 401, body: { error: 'two-factor', two_factor_required: true, challenge: 'ch1' } },
    { status: 401, body: { error: 'that code is not right' } },
    { status: 401, body: { error: 'too many wrong codes — start again with your password' } },
  ]);
  await sandbox.login();
  get('l-code').value = '000000';
  await sandbox.loginCode();
  assert.ok(/not right/.test(get('l-err').textContent));
  assert.ok(!get('l-2fa').hidden(), 'still asking');
  await sandbox.loginCode();
  assert.ok(get('l-2fa').hidden(), 'back to the password');
  assert.ok(!get('l-form').hidden());
});

check('sign-in: a wrong password is a message, not "session expired"', async () => {
  const { sandbox, get } = load({}, [], [
    { status: 401, body: { error: 'invalid email or password' } },
  ]);
  await sandbox.login();
  assert.strictEqual(get('l-err').textContent, 'invalid email or password');
});

check('sign-in with a recovery code warns how many are left', async () => {
  const { sandbox, get, toasts } = load({}, [], [
    { status: 401, body: { error: 'x', two_factor_required: true, challenge: 'c' } },
    { status: 200, body: { token: 't', user: { email: 'a@b' }, recovery_codes_left: 3 } },
  ]);
  await sandbox.login();
  get('l-code').value = 'abcd-efgh-jkmn-pqrs';
  await sandbox.loginCode();
  assert.ok(toasts.some((t) => /3 left/.test(t)), toasts.join(' | '));
});

check("People: an owner can clear someone else's 2FA, not their own", async () => {
  const { sandbox, get } = load({
    'GET /api/users': [
      { id: 'u1', email: 'owner@lib.test', display_name: 'Owner', is_master: true, two_factor: true },
      { id: 'u2', email: 'ana@lib.test', display_name: 'Ana', is_master: false, two_factor: true },
      { id: 'u3', email: 'bo@lib.test', display_name: 'Bo', is_master: false, two_factor: false },
    ],
    'GET /api/invites': [],
    'GET /api/mail/status': { enabled: false },
  });
  vm.runInContext("S.email = 'owner@lib.test'", sandbox);
  await sandbox.showPeople();
  const html = get('page').innerHTML;
  const clears = html.match(/data-act="clear2fa"[^>]*/g) || [];
  assert.strictEqual(clears.length, 1, html);
  assert.ok(clears[0].includes('data-id="u2"'));
  assert.ok(html.includes('2FA on'));
});

check('clearing asks first, then deletes', async () => {
  const { sandbox, calls, asked } = load(
    {
      'DELETE /api/users/u2/2fa': { ok: true },
      'GET /api/users': [],
      'GET /api/invites': [],
      'GET /api/mail/status': { enabled: false },
    },
    [{}],
  );
  await sandbox.clear2fa('u2', 'ana@lib.test');
  assert.ok(asked[0].danger);
  assert.ok(calls.some((c) => c.method === 'DELETE' && c.url === '/api/users/u2/2fa'));
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
