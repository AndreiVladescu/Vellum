// The console's overview page: what a person running a shared library sees on
// opening it, and what happens to it when the server refuses part of it.
//
// The rule being guarded: every section stands alone. A member is refused the
// server's numbers and the activity log; an older server has no notifications.
// Neither may take the page down, and neither may be mistaken for an empty
// library — "you may not see this" hides a section, "it broke" says so.
//
// Run with: node web/tests/overview_page.test.js

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

/// Loads the console with `api` replaced by a table of canned answers. An Error
/// in the table is thrown, which is how a refusal reaches the page.
function load(responses, { master = null } = {}) {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const calls = [];
  const sandbox = {
    document: {
      getElementById: get,
      querySelectorAll: () => [],
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
  sandbox.api = (method, url, body) => {
    calls.push({ method, url, body });
    const key = method + ' ' + url;
    if (!(key in responses)) return Promise.reject(new Error('unexpected ' + key));
    const r = responses[key];
    return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
  };
  vm.runInContext(`S.isMaster = ${JSON.stringify(master)}`, sandbox);
  return { sandbox, get, calls };
}

let failures = 0;
const pending = [];
function check(name, fn) {
  let timer;
  const guard = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timed out')), 5000);
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

const TODAY = '2026-03-10';

const refused = (status) => Object.assign(new Error('HTTP ' + status), { status });

function loan(title, borrower, due) {
  return {
    copy_id: 'c-' + title, book_id: 'b-' + title, book_title: title, location: null,
    loan_id: 'l-' + title, borrower, loaned_at: '2026-01-01 09:00:00',
    due_at: due ? due + ' 00:00:00' : null, can_edit: true,
  };
}
const SHELF = {
  copy_id: 'c-s', book_id: 'b-s', book_title: 'Solaris', location: null,
  loan_id: null, borrower: null, loaned_at: null, due_at: null, can_edit: true,
};

const OK = (data) => ({ ok: true, data });
const NO = (status) => ({ ok: false, status, message: 'HTTP ' + status });
const STATS = {
  books: 12, files: 9, users: 3, blob_bytes: 3 * 1024 * 1024, database_bytes: 1024 * 1024,
  server_version: '1.2.2',
};
const ALL_OK = () => ({
  books: OK({ total: 12, items: [] }),
  stats: OK(STATS),
  loans: OK([]),
  requests: OK([]),
  notes: OK({ unread: 0, notifications: [] }),
  audit: OK({ enabled: true, rows: [] }),
});

console.log('classifying loans');

check('overdue comes longest-late first, then due soon soonest first', () => {
  const { sandbox } = load({});
  const c = sandbox.classifyLoans([
    loan('Later', 'A', '2026-03-12'),
    loan('Recent', 'B', '2026-03-08'),
    loan('Ancient', 'C', '2026-01-01'),
    loan('Sooner', 'D', '2026-03-11'),
    loan('Far', 'E', '2026-06-01'),
    loan('Open', 'F', null),
    SHELF,
  ], TODAY);
  assert.deepEqual(c.overdue.map((l) => l.book_title), ['Ancient', 'Recent']);
  assert.deepEqual(c.soon.map((l) => l.book_title), ['Sooner', 'Later']);
  assert.strictEqual(c.out, 6);
  assert.strictEqual(c.copies, 7);
  assert.strictEqual(c.overdue[1].daysLate, 2);
});

check('a loan due today is due, not late; one with no date is neither', () => {
  const { sandbox } = load({});
  const c = sandbox.classifyLoans([loan('Today', 'A', TODAY), loan('Open', 'B', null)], TODAY);
  assert.strictEqual(c.overdue.length, 0);
  assert.deepEqual(c.soon.map((l) => l.book_title), ['Today']);
});

check('the window is a week, inclusive', () => {
  const { sandbox } = load({});
  const c = sandbox.classifyLoans([loan('In7', 'A', '2026-03-17'), loan('In8', 'B', '2026-03-18')], TODAY);
  assert.deepEqual(c.soon.map((l) => l.book_title), ['In7']);
});

check('days are counted across a month end, and put into words', () => {
  const { sandbox } = load({});
  assert.strictEqual(sandbox.daysBetween('2026-02-27', '2026-03-02'), 3);
  assert.strictEqual(sandbox.dueWords(1), '1 day late');
  assert.strictEqual(sandbox.dueWords(0), 'due today');
  assert.strictEqual(sandbox.dueWords(-1), 'due tomorrow');
  assert.strictEqual(sandbox.dueWords(-3), 'due in 3 days');
});

console.log('sections degrade on their own');

check('a member: no server numbers, no activity, but books and lending remain', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.stats = NO(403);
  r.audit = NO(403);
  const m = sandbox.buildOverview(r, TODAY, false);
  assert.deepEqual(m.counts.map((c) => c.label), ['Books']);
  assert.strictEqual(m.activity, null);
  assert.ok(m.lending && m.requests && m.notes);
});

check('a 404 (an older server) hides a section; a 500 shows that it failed', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.notes = NO(404);
  r.requests = NO(500);
  const m = sandbox.buildOverview(r, TODAY, true);
  assert.strictEqual(m.notes, null, '404: not there, so not shown');
  assert.strictEqual(m.requests.ok, false, '500: shown as broken');
  const html = sandbox.overviewHtml(m);
  assert.ok(html.includes('Could not load this'));
  assert.ok(!html.includes('Notifications'));
});

check('a known member is never shown the activity log; an unknown role is asked', () => {
  const { sandbox } = load({});
  assert.strictEqual(sandbox.buildOverview(ALL_OK(), TODAY, false).activity, null);
  assert.ok(sandbox.buildOverview(ALL_OK(), TODAY, true).activity);
  assert.ok(sandbox.buildOverview(ALL_OK(), TODAY, null).activity, 'the server decides');
});

check('everything refused still renders a page', () => {
  const { sandbox } = load({});
  const none = { books: NO(403), stats: NO(403), loans: NO(403), requests: NO(403), notes: NO(403), audit: NO(403) };
  const html = sandbox.overviewHtml(sandbox.buildOverview(none, TODAY, false));
  assert.ok(html.includes('Refresh'));
});

console.log('empty states and links');

check('no books: says what to do next, with Add book and Import', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.books = OK({ total: 0, items: [] });
  const html = sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true));
  assert.ok(html.includes('The library is empty'));
  assert.ok(html.includes('data-act="addbook"'));
  assert.ok(html.includes('data-id="import"'));
});

check('books present: no empty-library hint', () => {
  const { sandbox } = load({});
  const html = sandbox.overviewHtml(sandbox.buildOverview(ALL_OK(), TODAY, true));
  assert.ok(!html.includes('The library is empty'));
});

check('no copies, then copies with nothing due, then late ones', () => {
  const { sandbox } = load({});
  const render = (rows) => {
    const r = ALL_OK();
    r.loans = OK(rows);
    return sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true));
  };
  assert.ok(render([]).includes('No physical copies are recorded yet'));
  assert.ok(render([SHELF]).includes('Nothing is overdue or due this week'));
  const late = render([loan('Dune', 'Alice', '2026-03-01')]);
  assert.ok(late.includes('Overdue') && late.includes('9 days late') && late.includes('Dune'));
  assert.ok(late.includes('href="#/lending/loans"'));
});

check('waiting requests link to the requests page; none says so', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.requests = OK([
    { id: 'q1', status: 'pending', book_title: 'Dune', requester_email: 'a@x.test', created_at: '2026-03-09 10:00:00' },
    { id: 'q2', status: 'approved', book_title: 'Old', requester_email: 'b@x.test', created_at: '2026-01-01 10:00:00' },
  ]);
  const html = sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true));
  assert.ok(html.includes('Borrow requests (1 waiting)'));
  assert.ok(html.includes('href="#/lending/requests"'));
  assert.ok(!html.includes('>Old<') && !html.includes('Old</strong>'), 'an answered request is not waiting');
  const none = sandbox.overviewHtml(sandbox.buildOverview(ALL_OK(), TODAY, true));
  assert.ok(none.includes('Nobody is waiting on you'));
});

check('activity off: a one-line hint with the setting; on: the rows', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.audit = OK({ enabled: false, rows: [] });
  assert.ok(sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true)).includes('VELLUM_AUDIT=1'));
  r.audit = OK({
    enabled: true,
    rows: [{ action: 'book.delete', detail: 'Dune', actor_email: 'a@x.test', at: '2026-03-09T10:00:00Z' }],
  });
  const html = sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true));
  assert.ok(html.includes('book.delete') && html.includes('a@x.test') && html.includes('#/server/activity'));
});

check('the master sees the server counts, storage being database plus blobs', () => {
  const { sandbox } = load({});
  const m = sandbox.buildOverview(ALL_OK(), TODAY, true);
  assert.deepEqual(m.counts.map((c) => c.label), ['Books', 'Files', 'People', 'Storage']);
  assert.strictEqual(m.counts[3].value, '4.0 MB');
});

check('server-provided strings are escaped', () => {
  const { sandbox } = load({});
  const r = ALL_OK();
  r.loans = OK([loan('<img src=x onerror=alert(1)>', '<b>Eve</b>', '2026-03-01')]);
  r.notes = OK({ unread: 1, notifications: [{ title: '<script>x</script>', created_at: '2026-03-09', read_at: null }] });
  const html = sandbox.overviewHtml(sandbox.buildOverview(r, TODAY, true));
  assert.ok(!html.includes('<img') && !html.includes('<b>Eve') && !html.includes('<script>'));
});

console.log('the page');

check('the owner: every endpoint is asked once and the page opens', async () => {
  const { sandbox, get, calls } = load({
    'GET /api/books?page=1&limit=1': { total: 1, items: [] },
    'GET /api/admin/stats': STATS,
    'GET /api/loans/overview': [loan('Dune', 'Alice', '2026-01-01')],
    'GET /api/borrow-requests?direction=incoming': [],
    'GET /api/notifications?unread=1&limit=5': { unread: 0, notifications: [] },
    'GET /api/admin/audit?limit=8': { enabled: false, rows: [] },
  }, { master: true });
  await sandbox.showOverview();
  assert.strictEqual(calls.length, 6);
  assert.strictEqual(get('page').hidden(), false);
  assert.ok(get('page').innerHTML.includes('Dune'));
});

check('a member is not asked for the owner-only endpoints, and the page still opens', async () => {
  const { sandbox, get, calls } = load({
    'GET /api/books?page=1&limit=1': { total: 1, items: [] },
    'GET /api/loans/overview': [],
    'GET /api/borrow-requests?direction=incoming': refused(500),
    'GET /api/notifications?unread=1&limit=5': refused(404),
  }, { master: false });
  await sandbox.showOverview();
  assert.ok(!calls.some((c) => c.url.startsWith('/api/admin')), 'nothing owner-only requested');
  const html = get('page').innerHTML;
  assert.ok(html.includes('Overview'));
  assert.ok(html.includes('Could not load this'), 'the 500 is visible');
  assert.ok(!html.includes('Notifications'), 'the 404 is not');
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failed`);
    process.exit(1);
  }
  console.log('\nall passed');
});
