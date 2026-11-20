// Secrets are read back exactly as typed (v1.6.x).
//
// A password with a leading or trailing space is a different password. The
// console's prompt dialog used to trim every field, so on the two-factor page
// such a password could be set at sign-in and then never confirmed. What is
// worth defending: `ask()` leaves password (and `secret: true`) fields alone
// while still trimming ordinary text, the link-password and register forms send
// what was typed, and nothing in the console trims a field that holds a secret.
//
// Run with: node web/tests/secret_fields.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = require('./console_source.js')();

function element(id) {
  return {
    id,
    innerHTML: '',
    value: '',
    checked: false,
    classList: { add() {}, remove() {}, contains: () => false, toggle() {} },
    focus() {},
    select() {},
    addEventListener() {},
  };
}

function load() {
  const els = new Map();
  const get = (id) => {
    // A dialog's inputs exist only as far as its markup says: `askDone` walks
    // `ask-0`, `ask-1`, ... until one is missing, so answering for ids the
    // dialog never drew would never end.
    if (/^ask-\d+$/.test(id) && !els.has(id)) {
      const root = els.get('modal-root');
      if (!(root && root.innerHTML.includes(`id="${id}"`))) return null;
    }
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const calls = [];
  const sandbox = {
    document: {
      getElementById: get,
      querySelectorAll: () => [],
      createElement: () => element('made'),
      addEventListener() {},
      body: { appendChild() {} },
      documentElement: { style: { setProperty() {} } },
    },
    window: {
      addEventListener() {},
      matchMedia: () => ({ matches: false, addEventListener() {} }),
      scrollTo() {},
    },
    location: { origin: 'https://books.example', hash: '' },
    localStorage: { getItem: () => null, setItem() {} },
    sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: {},
    console,
    setTimeout,
    clearTimeout,
    URL,
    btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
    Blob: class {},
    Promise,
    addEventListener() {},
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    requestAnimationFrame() {},
    scrollTo() {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  sandbox.api = (method, url, body) => {
    calls.push({ method, url, body: body && JSON.parse(JSON.stringify(body)) });
    return Promise.resolve({ url: 'https://books.example/s/x', token: 't', user: { email: 'a@b.c' } });
  };
  sandbox.toast = () => {};
  sandbox.showApp = () => {};
  return { sandbox, get, calls };
}

let failures = 0;
const pending = [];
function check(name, fn) {
  pending.push(
    Promise.resolve()
      .then(fn)
      .then(() => console.log('  ok   ' + name))
      .catch((e) => {
        failures++;
        console.log('  FAIL ' + name + '\n       ' + e.message);
      }),
  );
}

check('a password field comes back exactly as typed, spaces and all', async () => {
  const { sandbox, get } = load();
  const asked = sandbox.ask({ title: 'Confirm', fields: [{ label: 'Password', type: 'password' }] });
  get('ask-0').value = '  correct horse  ';
  sandbox.askDone(true);
  const answer = await asked;
  assert.strictEqual(answer[0], '  correct horse  ');
});

check('a secret shown in the clear is not trimmed either', async () => {
  const { sandbox, get } = load();
  const asked = sandbox.ask({ title: 'Key', fields: [{ label: 'Key', secret: true }] });
  get('ask-0').value = ' k ';
  sandbox.askDone(true);
  assert.strictEqual((await asked)[0], ' k ');
});

check('ordinary text fields are still trimmed, beside a secret', async () => {
  const { sandbox, get } = load();
  const asked = sandbox.ask({
    title: 'Mixed',
    fields: [{ label: 'Name' }, { label: 'Password', type: 'password' }, { label: 'Note' }],
  });
  get('ask-0').value = '  Ana  ';
  get('ask-1').value = ' pw ';
  get('ask-2').value = ' note\n';
  sandbox.askDone(true);
  const answer = await asked;
  assert.deepStrictEqual({ ...answer }, { 0: 'Ana', 1: ' pw ', 2: 'note' });
});

check('the secret marking does not leak into the next dialog', async () => {
  const { sandbox, get } = load();
  const first = sandbox.ask({ title: 'A', fields: [{ label: 'P', type: 'password' }] });
  sandbox.askDone(false);
  await first;
  const second = sandbox.ask({ title: 'B', fields: [{ label: 'Name' }] });
  get('ask-0').value = ' x ';
  sandbox.askDone(true);
  assert.strictEqual((await second)[0], 'x');
});

check('a link password is sent untrimmed', async () => {
  const { sandbox, get, calls } = load();
  get('m-pw').value = ' open sesame ';
  await sandbox.createLink('book1');
  assert.strictEqual(calls[0].body.password, ' open sesame ');
});

check('registering sends the password (and bootstrap token) as typed', async () => {
  const { sandbox, get, calls } = load();
  get('r-email').value = ' a@b.c ';
  get('r-name').value = ' Ana ';
  get('r-pass').value = ' spaced pass ';
  get('r-token').value = ' tok ';
  await sandbox.register();
  const body = calls.find((c) => c.url === '/api/auth/register').body;
  assert.strictEqual(body.email, 'a@b.c');
  assert.strictEqual(body.display_name, 'Ana');
  assert.strictEqual(body.password, ' spaced pass ');
  assert.strictEqual(body.bootstrap_token, ' tok ');
});

check('nothing in the console trims a line that handles a password or token', () => {
  const dir = path.join(__dirname, '..', 'console');
  const offenders = [];
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.js'))) {
    fs.readFileSync(path.join(dir, f), 'utf8')
      .split('\n')
      .forEach((line, i) => {
        const code = line.replace(/\/\/.*$/, '');
        // The one place that trims on purpose: ask() trims everything *except*
        // the fields it was told are secret.
        if (code.includes('_askSecret.has(')) return;
        if (/\.trim\(\)/.test(code) && /pass(word)?\b|\bpw\b|secret|bootstrap|'r-token'|\btyped\b/i.test(code)) {
          offenders.push(`${f}:${i + 1}: ${line.trim()}`);
        }
      });
  }
  assert.deepStrictEqual(offenders, []);
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
