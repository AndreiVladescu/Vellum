// The console's first-run branch: on a server with no accounts, show the
// "create the master account" form instead of a login box nobody can use.
//
// Same shallow approach as import_parse.test.js — console.js is a browser
// script, so it is loaded into a context with a DOM stub just deep enough for
// these three functions. What is asserted here is the *decision* (which form is
// shown, whether the bootstrap-token field appears), not layout. The server
// side of the contract is `tests/api.rs`.
//
// Run with: node web/tests/first_run.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

/// One stub element, remembering whether it is hidden. `classList.contains` is
/// what register() reads to decide whether to send a bootstrap token, so it has
/// to be honest rather than a no-op.
function element() {
  const classes = new Set();
  return {
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c),
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
    },
    value: '',
    textContent: '',
    focus() {},
    // A successful register() lands in showApp(), which toasts; the toast
    // removes itself on a timer after the assertions are done.
    remove() {},
    hidden: () => classes.has('hidden'),
  };
}

/// The ids that carry `class="hidden"` in console.html. Seeded so the stubs
/// start where the real markup starts — otherwise "did nothing" and "revealed
/// the form" look identical.
const HIDDEN_AT_LOAD = ['register', 'r-token', 'l-to-register', 'app'];

/// A fresh sandbox per case: `fetch` answers `/api/auth/registration` with
/// [reply], and every element id resolves to its own stub.
function load(reply) {
  const els = new Map();
  for (const id of HIDDEN_AT_LOAD) {
    const e = element();
    e.classList.add('hidden');
    els.set(id, e);
  }
  const sandbox = {
    document: {
      getElementById: (id) => {
        if (!els.has(id)) els.set(id, element());
        return els.get(id);
      },
      createElement: () => element(),
      addEventListener: () => {},
      body: { appendChild: () => {} },
      documentElement: { style: { setProperty: () => {} } },
    },
    window: { addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener: () => {} }) },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: async () => reply(),
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
  return { sandbox, el: (id) => sandbox.document.getElementById(id) };
}

const json = (status, body) => () => ({
  status,
  ok: status < 400,
  json: async () => body,
});

let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log('  ok   ' + name);
  } catch (e) {
    failures++;
    console.log('  FAIL ' + name + '\n       ' + e.message);
  }
}

async function main() {
  console.log('checkRegistration');

  await check('an open server shows the register form', async () => {
    const { sandbox, el } = load(json(200, { open: true, bootstrap_token_required: false }));
    await sandbox.checkRegistration();
    assert.strictEqual(el('register').hidden(), false, 'register form is shown');
    assert.strictEqual(el('login').hidden(), true, 'login form is hidden');
    assert.strictEqual(el('r-token').hidden(), true, 'no bootstrap token asked for');
  });

  await check('a closed server leaves the login form alone', async () => {
    const { sandbox, el } = load(json(200, { open: false, bootstrap_token_required: false }));
    await sandbox.checkRegistration();
    assert.strictEqual(el('register').hidden(), true, 'register form stays hidden');
    assert.strictEqual(el('login').hidden(), false, 'login form is still the one on screen');
  });

  await check('a bootstrap-protected server asks for the token', async () => {
    const { sandbox, el } = load(json(200, { open: true, bootstrap_token_required: true }));
    await sandbox.checkRegistration();
    assert.strictEqual(el('r-token').hidden(), false, 'token field is revealed');
  });

  await check('an older server without the route changes nothing', async () => {
    const { sandbox, el } = load(json(404, { error: 'not found' }));
    await sandbox.checkRegistration();
    assert.strictEqual(el('login').hidden(), false, 'login form survives the 404');
  });

  console.log('\nregister');

  await check('sends the token only when the field is showing', async () => {
    let sent = null;
    const { sandbox, el } = load(json(200, { open: true, bootstrap_token_required: true }));
    await sandbox.checkRegistration();
    el('r-email').value = 'owner@example.com';
    el('r-name').value = 'Owner';
    el('r-pass').value = 'long-enough';
    el('r-token').value = 'secret';
    sandbox.fetch = async (_path, init) => {
      sent = JSON.parse(init.body);
      return json(200, { token: 't', user: { email: 'owner@example.com' } })();
    };
    await sandbox.register();
    assert.strictEqual(sent.bootstrap_token, 'secret');
    assert.strictEqual(sent.display_name, 'Owner');
  });

  await check('omits the token when the server never asked for one', async () => {
    let sent = null;
    const { sandbox, el } = load(json(200, { open: true, bootstrap_token_required: false }));
    await sandbox.checkRegistration();
    el('r-email').value = 'owner@example.com';
    el('r-name').value = 'Owner';
    el('r-pass').value = 'long-enough';
    sandbox.fetch = async (_path, init) => {
      sent = JSON.parse(init.body);
      return json(200, { token: 't', user: { email: 'owner@example.com' } })();
    };
    await sandbox.register();
    assert.strictEqual('bootstrap_token' in sent, false);
  });

  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
}

main();
