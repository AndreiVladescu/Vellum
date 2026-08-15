// Telling the operator whether this server can send mail.
//
// Setting SMTP up is five environment variables and a restart, and until now
// the console said nothing about any of it: an invitation simply came back as a
// link, with no hint that it could have been emailed. So the People screen now
// says which state it is in, and offers the one action that proves it.
//
// Run with: node web/tests/mail_setup.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

function element(id) {
  const classes = new Set(id === 'page' ? ['hidden'] : []);
  return {
    id, innerHTML: '', value: '', textContent: '',
    classList: {
      add: (c) => classes.add(c), remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c), toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
    },
    remove() {}, focus() {}, select() {},
    getBoundingClientRect: () => ({ height: 0, width: 0, top: 0, left: 0 }),
    querySelector: () => element('inner'), querySelectorAll: () => [],
    appendChild() {}, addEventListener() {},
  };
}

function load(responses) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
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
    window: { addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener: () => {} }), scrollTo: () => {} },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: {}, console, setTimeout, clearTimeout, URL, Blob: class {}, Promise,
    addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener: () => {} }),
    requestAnimationFrame: () => {}, scrollTo: () => {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  sandbox.api = (method, url, body) => {
    calls.push({ method, url, body });
    const key = method + ' ' + url;
    if (!(key in responses)) return Promise.reject(new Error('unexpected ' + key));
    const answer = responses[key];
    return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(answer);
  };
  sandbox.toast = (m) => toasts.push(m);
  return { sandbox, get, calls, toasts };
}

let failures = 0;
const pending = [];
function check(name, fn) {
  let timer;
  const guard = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timed out — did something wait for a click?')), 5000);
  });
  pending.push(
    Promise.race([Promise.resolve().then(fn), guard])
      .then(() => console.log('  ok   ' + name))
      .catch((e) => { failures++; console.log('  FAIL ' + name + '\n       ' + e.message); })
      .finally(() => clearTimeout(timer)),
  );
}

const PEOPLE = {
  'GET /api/users': [{ id: 'u1', email: 'owner@lib.test', display_name: 'Owner', is_master: true }],
  'GET /api/invites': [],
};

console.log('Mail setup');

check('a server with no relay says so, and offers the way in', async () => {
  const { sandbox, get } = load({ ...PEOPLE, 'GET /api/mail/status': { enabled: false } });
  await sandbox.showPeople();
  const html = get('page').innerHTML;

  assert.ok(html.includes('Email is off'), 'the state is on screen');
  assert.ok(html.includes('data-act="mailhelp"'), 'with somewhere to go');
  assert.ok(!html.includes('data-act="mailtest"'), 'nothing to test yet');
});

check('a configured server names its sender and offers a test', async () => {
  const { sandbox, get } = load({
    ...PEOPLE,
    'GET /api/mail/status': { enabled: true, from: 'vellum@lib.test' },
  });
  await sandbox.showPeople();
  const html = get('page').innerHTML;

  assert.ok(html.includes('Email is on'), 'says it works');
  assert.ok(html.includes('vellum@lib.test'), 'and as whom — the usual mistake');
  assert.ok(html.includes('data-act="mailtest"'), 'and proves it on request');
});

check('an older server without the endpoint is treated as off, not broken', async () => {
  // The People screen must still render: mail is the least of what it shows.
  const { sandbox, get } = load({
    ...PEOPLE,
    'GET /api/mail/status': new Error('404 not found'),
  });
  await sandbox.showPeople();
  const html = get('page').innerHTML;

  assert.ok(html.includes('owner@lib.test'), 'the people are still listed');
  assert.ok(html.includes('Email is off'));
});

check('a test send reports the address it went to', async () => {
  const { sandbox, toasts } = load({ 'POST /api/mail/test': { sent_to: 'owner@lib.test' } });
  await sandbox.testMail();
  assert.ok(/owner@lib\.test/.test(toasts.join(' ')), toasts.join(' '));
});

check('a refused test shows the relay’s own words', async () => {
  // The whole point: "535 Username and Password not accepted" names the
  // variable to fix, where a tidy summary would not.
  const { sandbox, toasts } = load({
    'POST /api/mail/test': new Error('the mail server refused it: 535 Username and Password not accepted'),
  });
  await sandbox.testMail();
  assert.ok(/535/.test(toasts.join(' ')), `kept verbatim: ${toasts.join(' ')}`);
});

check('the setup dialog lists every variable that matters', async () => {
  const { sandbox, get } = load({});
  sandbox.showMailSetup();
  const html = get('modal-root').innerHTML;

  for (const v of ['VELLUM_SMTP_HOST', 'VELLUM_SMTP_PORT', 'VELLUM_SMTP_USER',
                   'VELLUM_SMTP_PASS', 'VELLUM_MAIL_FROM']) {
    assert.ok(html.includes(v), `${v} is missing from the instructions`);
  }
  assert.ok(html.includes('app'), 'and the Gmail app-password trap');
  assert.ok(!html.includes('null'), 'a dialog with nothing to cancel shows no Cancel');
});

Promise.all(pending).then(() => {
  if (failures) { console.log(`\n${failures} failing`); process.exit(1); }
  console.log('\nall passed');
});
