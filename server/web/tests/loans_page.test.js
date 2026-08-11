// The console's Loans page, and the button it must not offer.
//
// The reported problem was a "Lend it" button on a borrow request that could
// not possibly work: the only copy of the book was already out, so pressing it
// produced an error and the owner's only real option was Decline. A button
// whose sole outcome is an error is worse than no button — it has to say why
// instead. The other half is being able to lend at all from the console, which
// there was no way to do.
//
// Run with: node web/tests/loans_page.test.js

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

const OVERVIEW = [
  {
    copy_id: 'c-out',
    book_id: 'b-dune',
    book_title: 'Dune',
    location: 'living room',
    loan_id: 'l1',
    borrower: 'Alice',
    loaned_at: '2026-01-01 09:00:00',
    due_at: '2026-03-01 00:00:00',
    can_edit: true,
  },
  {
    copy_id: 'c-free',
    book_id: 'b-solaris',
    book_title: 'Solaris',
    location: null,
    loan_id: null,
    borrower: null,
    loaned_at: null,
    due_at: null,
    can_edit: true,
  },
];

console.log('Loans page');

check('shows who has a copy, and which copies are free', async () => {
  const { sandbox, get } = load({ 'GET /api/loans/overview': OVERVIEW });
  await sandbox.showLoans();
  const html = get('page').innerHTML;

  assert.ok(html.includes('Dune'), 'the lent book');
  assert.ok(html.includes('Alice'), 'and who has it');
  assert.ok(html.includes('2026-01-01'), 'since when');
  assert.ok(html.includes('Solaris'), 'the free copy is listed too');
  assert.ok(html.includes('On the shelf'), 'and says so');
  assert.ok(html.includes('1 of 2 copies are out'), 'the summary counts copies');
});

check('offers Lend on a free copy and Mark returned on a lent one', async () => {
  const { sandbox, get } = load({ 'GET /api/loans/overview': OVERVIEW });
  await sandbox.showLoans();
  const html = get('page').innerHTML;

  assert.ok(html.includes('data-act="lendcopy"'), 'the free copy can be lent');
  assert.ok(html.includes('data-copy="c-free"'), 'and it is the free one');
  assert.ok(html.includes('data-act="returncopy"'), 'the lent copy can come back');
  assert.ok(html.includes('data-loan="l1"'), 'naming the loan to close');
});

check('a reader gets the state and no buttons', async () => {
  const readOnly = OVERVIEW.map((r) => ({ ...r, can_edit: false }));
  const { sandbox, get } = load({ 'GET /api/loans/overview': readOnly });
  await sandbox.showLoans();
  const html = get('page').innerHTML;

  assert.ok(html.includes('Alice'), 'they can still see where the book is');
  assert.ok(!html.includes('data-act="lendcopy"'), 'but cannot lend it');
  assert.ok(!html.includes('data-act="returncopy"'), 'nor take it back');
});

check('lending sends the copy, the borrower and a timestamp', async () => {
  const { sandbox, calls } = load({
    'GET /api/loans/overview': OVERVIEW,
    'PUT /api/loans/11111111-2222-4333-8444-555555555555': {},
  });
  const answers = ['Bob', '2026-06-01'];
  sandbox.prompt = () => answers.shift();
  await sandbox.lendCopyFromConsole('c-free');

  const put = calls.find((c) => c.method === 'PUT');
  assert.ok(put, 'a loan was created');
  assert.strictEqual(put.body.copy_id, 'c-free');
  assert.strictEqual(put.body.borrower, 'Bob');
  assert.strictEqual(put.body.due_at, '2026-06-01 00:00:00');
  assert.match(put.body.loaned_at, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/,
    'the server format, not an ISO string with a T in it');
});

check('cancelling the borrower prompt records nothing', async () => {
  const { sandbox, calls } = load({});
  sandbox.prompt = () => null;
  await sandbox.lendCopyFromConsole('c-free');
  assert.strictEqual(calls.length, 0, 'no half-made loan left behind');
});

check('a return closes the loan and keeps its immutable fields', async () => {
  const { sandbox, calls } = load({
    'GET /api/loans/overview': OVERVIEW,
    'PUT /api/loans/l1': {},
  });
  await sandbox.returnCopyFromConsole('l1', 'c-out', 'Alice', '2026-01-01 09:00:00');

  const put = calls.find((c) => c.method === 'PUT');
  // copy_id and loaned_at cannot change on an existing loan; sending them back
  // altered — or not at all — is refused by the server.
  assert.strictEqual(put.body.copy_id, 'c-out');
  assert.strictEqual(put.body.loaned_at, '2026-01-01 09:00:00');
  assert.strictEqual(put.body.borrower, 'Alice');
  assert.ok(put.body.returned_at, 'and it is now returned');
});

console.log('\nBorrow requests');

const REQUEST = {
  id: 'r1',
  book_id: 'b-dune',
  book_title: 'Dune',
  requester_email: 'reader@lib.test',
  status: 'pending',
  note: null,
};

check('a request for a book that is out cannot be lent, and says why', async () => {
  const { sandbox, get } = load({
    'GET /api/borrow-requests?direction=incoming': [REQUEST],
    'GET /api/loans/overview': OVERVIEW,
  });
  await sandbox.showRequests();
  const html = get('page').innerHTML;

  assert.ok(html.includes('data-decision="declined"'), 'declining is still offered');
  assert.ok(!html.includes('data-decision="approved"'),
    'but not a Lend button that could only fail');
  assert.ok(html.includes('every copy is with Alice'), 'the reason is on screen');
});

check('a request for a book with a free copy can be lent', async () => {
  const solaris = { ...REQUEST, book_id: 'b-solaris', book_title: 'Solaris' };
  const { sandbox, get } = load({
    'GET /api/borrow-requests?direction=incoming': [solaris],
    'GET /api/loans/overview': OVERVIEW,
  });
  await sandbox.showRequests();
  const html = get('page').innerHTML;

  assert.ok(html.includes('data-decision="approved"'), 'the copy is on the shelf');
  assert.ok(!html.includes('Can’t lend'), 'so no explanation is needed');
});

check('a book with no copies at all says that, not "someone has it"', async () => {
  const ghost = { ...REQUEST, book_id: 'b-nothing', book_title: 'A book with no copies' };
  const { sandbox, get } = load({
    'GET /api/borrow-requests?direction=incoming': [ghost],
    'GET /api/loans/overview': OVERVIEW,
  });
  await sandbox.showRequests();
  const html = get('page').innerHTML;

  assert.ok(html.includes('no physical copy is on record'), 'the true reason');
  assert.ok(!html.includes('data-decision="approved"'));
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
});
