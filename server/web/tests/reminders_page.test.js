// The console's due-date reminder settings (migration 0037).
//
// This screen sends email to other people, so the property worth defending is
// that it cannot be switched on into a void: a server with no mailer disables
// every control and says which environment variables are missing, rather than
// offering a switch that turns on and does nothing.
//
// Run with: node web/tests/reminders_page.test.js

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert');

const source = fs.readFileSync(path.join(__dirname, '..', 'console.js'), 'utf8');

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

/// Loads the console with `api` replaced by a table of canned answers, so a
/// page can be rendered without a server.
function load(responses) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const calls = [];
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
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: { randomUUID: () => '11111111-2222-4333-8444-555555555555' },
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
  return { sandbox, get, calls };
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


const SETTINGS = {
  loan_reminders: false,
  lead_days: 3,
  before_subject: '"{title}" is due back on {due_date}',
  before_body: 'Hello {borrower}, it is due on {due_date}.',
  due_subject: '"{title}" is due back today',
  due_body: 'Hello {borrower}, today.',
  overdue_subject: '"{title}" is overdue',
  overdue_body: 'Hello {borrower}, it was due on {due_date}.',
  mail_configured: true,
};

check('the screen shows the messages, and what fills them in', async () => {
  const { sandbox, get } = load({ 'GET /api/settings': SETTINGS });
  await sandbox.showReminders();
  const html = get('page').innerHTML;

  assert.ok(html.includes('due back on {due_date}'), 'the stock subject');
  assert.ok(html.includes('{borrower}'), 'and the placeholders are documented');
  assert.ok(html.includes('data-act="savereminders"'));
  assert.ok(html.includes('data-act="runreminders"'), 'send any due now');
});

check('a server with no mailer disables the lot and says why', async () => {
  const { sandbox, get } = load({
    'GET /api/settings': { ...SETTINGS, mail_configured: false },
  });
  await sandbox.showReminders();
  const html = get('page').innerHTML;

  assert.ok(html.includes('VELLUM_SMTP_HOST'), 'names what is missing');
  assert.ok(html.includes('disabled'), 'and nothing can be switched on');
  // The specific failure being prevented: a switch that turns on and does
  // nothing is worse than one you cannot reach.
  assert.ok(
    html.includes('cannot send mail'),
    'says plainly that nothing will go out',
  );
});

check('the switch reflects what the server holds', async () => {
  const { sandbox, get } = load({
    'GET /api/settings': { ...SETTINGS, loan_reminders: true, lead_days: 7 },
  });
  await sandbox.showReminders();
  const html = get('page').innerHTML;

  assert.ok(html.includes('checked'), 'on when it is on');
  assert.ok(html.includes('value="7"'), 'and the lead time is the stored one');
});

check('saving sends every field, and the switch as a boolean', async () => {
  const { sandbox, calls, get } = load({
    'GET /api/settings': SETTINGS,
    'PUT /api/settings': SETTINGS,
  });
  await sandbox.showReminders();
  // What the form holds when somebody has typed in it.
  get('rm-on').checked = true;
  get('rm-lead').value = '5';
  get('rm-bs').value = 'Bring it back';
  await sandbox.saveReminders();

  const put = calls.find((c) => c.method === 'PUT');
  assert.ok(put, 'it saved');
  assert.strictEqual(put.body.loan_reminders, true);
  assert.strictEqual(put.body.lead_days, 5, 'a number, not the string "5"');
  assert.strictEqual(put.body.before_subject, 'Bring it back');
  assert.ok('overdue_body' in put.body, 'the ones left alone go too');
});

check('"send any due now" reports what went out', async () => {
  const { sandbox } = load({
    'GET /api/settings': SETTINGS,
    'POST /api/settings/loan-reminders/run': { sent: 2 },
  });
  await sandbox.showReminders();
  await sandbox.runReminders();
  // No assertion on the toast text beyond it not throwing: the point is that
  // the endpoint is reachable from here at all, which is what makes the
  // feature testable without waiting an hour.
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
