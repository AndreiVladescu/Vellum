// The console's Server page: version, storage, the settings in effect, and the
// two maintenance actions that used to be reachable only with curl.
//
// What is guarded: the page never looks anything up on its own (the releases
// page is a plain link), a secret can only appear as a yes/no, and the sweep —
// which deletes files — says what it will delete and how much before it does,
// and does nothing at all if the confirmation is dismissed.
//
// Run with: node web/tests/server_page.test.js

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

function load(responses = {}) {
  const els = new Map();
  const get = (id) => {
    // A dialog's inputs are looked up until one is missing; this has none.
    if (id.startsWith('ask-')) return null;
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
  return { sandbox, get, calls };
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
      .catch((e) => {
        failures++;
        console.log('  FAIL ' + name + '\n       ' + e.message);
      })
      .finally(() => clearTimeout(timer)),
  );
}

const STATS = {
  books: 12, authors: 8, users: 3, files: 9, shares: 1, share_links: 2,
  blob_bytes: 3 * 1024 * 1024, database_bytes: 512 * 1024, server_version: '1.2.2',
};
const CAPS = { server_version: '1.2.2', sync_protocol: 1, features: ['delta_pull', 'opds'] };
const CONFIG = {
  port: 3000, public_url: 'https://books.example.com', data_dir: '/data', database_path: '/data/vellum.db',
  max_upload_mb: 2048, tls: false, mail: true, text_indexing: false, audit_log: true, bootstrap_token: true,
};
const OK = (data) => ({ ok: true, data });
const refused = (status) => Object.assign(new Error('HTTP ' + status), { status });

const CLEAN = { missing_files: [], missing_covers: [], orphan_blobs: [], orphan_bytes: 0, deleted: 0 };
const DIRTY = {
  missing_files: ['f1: files/aa/x.pdf'],
  missing_covers: [],
  orphan_blobs: ['files/bb/stray.pdf', 'covers/old.jpg'],
  orphan_bytes: 5 * 1024 * 1024,
  deleted: 0,
};

console.log('rendering');

check('shows the running version beside a plain link to the releases page', () => {
  const { sandbox } = load();
  const html = sandbox.serverHtml({ stats: OK(STATS), config: OK(CONFIG), caps: OK(CAPS) });
  assert.ok(html.includes('Vellum server 1.2.2'));
  assert.ok(html.includes('href="https://github.com/AndreiVladescu/Vellum/releases"'));
  assert.ok(html.includes('rel="noopener noreferrer"'));
  assert.ok(html.includes('delta_pull') && html.includes('opds'), 'the capabilities');
});

check('the page itself never fetches anything but the three server endpoints', async () => {
  const { sandbox, calls } = load({
    'GET /api/admin/stats': STATS,
    'GET /api/admin/config': CONFIG,
    'GET /api/capabilities': CAPS,
  });
  await sandbox.showServer();
  assert.deepEqual(calls.map((c) => c.url).sort(),
    ['/api/admin/config', '/api/admin/stats', '/api/capabilities']);
});

check('storage lines carry sizes in words, WAL included', () => {
  const { sandbox } = load();
  const html = sandbox.serverHtml({ stats: OK(STATS), config: OK(CONFIG), caps: OK(CAPS) });
  assert.ok(html.includes('3.0 MB') && html.includes('512.0 KB'));
  assert.ok(html.includes('Database (including WAL)'));
});

check('configuration: booleans become words and the setting that turns each on is named', () => {
  const { sandbox } = load();
  const rows = Object.fromEntries(sandbox.configRows({ ...CONFIG, mail: false, text_indexing: false }));
  assert.strictEqual(rows['Email'], 'not configured');
  assert.ok(rows['Searching inside books'].includes('VELLUM_INDEX_TEXT=1'));
  assert.strictEqual(rows['Largest upload'], '2048 MB');
  assert.ok(rows['First-account token'].includes('required'));
  assert.ok(!JSON.stringify(rows).includes('true'), 'no raw booleans');
});

check('without the config endpoint (an older server) the section is simply absent', () => {
  const { sandbox } = load();
  const html = sandbox.serverHtml({
    stats: OK(STATS), config: { ok: false, status: 404, message: 'HTTP 404' }, caps: OK(CAPS),
  });
  assert.ok(!html.includes('Configuration in effect'));
  assert.ok(html.includes('Maintenance'), 'the rest stays');
});

check('server-provided strings are escaped', () => {
  const { sandbox } = load();
  const html = sandbox.serverHtml({
    stats: OK(STATS),
    config: OK({ ...CONFIG, public_url: '<img src=x onerror=alert(1)>' }),
    caps: OK({ ...CAPS, features: ['<script>x</script>'] }),
  });
  assert.ok(!html.includes('<img') && !html.includes('<script>'));
  const swept = sandbox.sweepHtml({ ...DIRTY, orphan_blobs: ['<b>x</b>'] });
  assert.ok(!swept.includes('<b>x'));
});

check('a refused stats call opens nothing and says why; other failures still open the page', async () => {
  const a = load({
    'GET /api/admin/stats': refused(403),
    'GET /api/admin/config': refused(403),
    'GET /api/capabilities': CAPS,
  });
  await a.sandbox.showServer();
  assert.strictEqual(a.get('page').hidden(), true);
  const b = load({
    'GET /api/admin/stats': refused(500),
    'GET /api/admin/config': CONFIG,
    'GET /api/capabilities': CAPS,
  });
  await b.sandbox.showServer();
  assert.strictEqual(b.get('page').hidden(), false);
  assert.ok(b.get('page').innerHTML.includes('Could not load this'));
});

console.log('the orphan check');

check('a clean report says nothing is out of step and offers no delete', () => {
  const { sandbox } = load();
  const html = sandbox.sweepHtml(CLEAN);
  assert.ok(html.includes('Nothing is out of step'));
  assert.ok(!html.includes('data-act="sweepdelete"'));
});

check('a report counts what it found, lists it, and offers the delete', () => {
  const { sandbox } = load();
  const html = sandbox.sweepHtml(DIRTY);
  assert.ok(html.includes('1 attached file is missing from disk'));
  assert.ok(html.includes('2 files on disk are used by no book (5.0 MB)'));
  assert.ok(html.includes('files/bb/stray.pdf'));
  assert.ok(html.includes('data-act="sweepdelete"'));
});

check('long lists are cut with a count of the rest', () => {
  const { sandbox } = load();
  const many = Array.from({ length: 25 }, (_, i) => `files/aa/${i}.pdf`);
  const html = sandbox.sweepHtml({ ...DIRTY, orphan_blobs: many });
  assert.ok(html.includes('and 15 more'));
  assert.ok(!html.includes('files/aa/24.pdf'));
});

check('the confirmation names the count and the bytes, and that it is permanent', () => {
  const { sandbox } = load();
  const text = sandbox.sweepConfirmBody(DIRTY);
  assert.ok(text.includes('2 files') && text.includes('5.0 MB'));
  assert.ok(text.includes('permanently') && text.includes('cannot be undone'));
  assert.ok(sandbox.sweepConfirmBody({ ...DIRTY, orphan_blobs: ['x'] }).includes('1 file '));
});

check('checking sends a plain POST, with no delete flag', async () => {
  const { sandbox, calls } = load({ 'POST /api/admin/sweep': DIRTY });
  await sandbox.checkOrphans();
  assert.deepEqual(calls.map((c) => c.method + ' ' + c.url), ['POST /api/admin/sweep']);
});

check('nothing is deleted until the dialog is confirmed; dismissing sends nothing', async () => {
  const { sandbox, get, calls } = load({
    'POST /api/admin/sweep': DIRTY,
    'POST /api/admin/sweep?delete_orphans=true': { ...DIRTY, deleted: 2 },
  });
  await sandbox.checkOrphans();
  const asked = sandbox.deleteOrphans();
  const dialog = get('modal-root').innerHTML;
  assert.ok(dialog.includes('Delete orphaned files?'));
  assert.ok(dialog.includes('2 files') && dialog.includes('5.0 MB'), 'the dialog states what goes');
  sandbox.askDone(false);
  await asked;
  assert.strictEqual(calls.length, 1, 'only the check ran');

  const again = sandbox.deleteOrphans();
  sandbox.askDone(true);
  await again;
  assert.strictEqual(calls[1].url, '/api/admin/sweep?delete_orphans=true');
  const after = get('sweep-report').innerHTML;
  assert.ok(after.includes('Deleted 2 files'));
  assert.ok(!after.includes('data-act="sweepdelete"'), 'the button is gone once used');
});

check('deleting with no report in hand does nothing', async () => {
  const { sandbox, calls } = load();
  await sandbox.deleteOrphans();
  assert.strictEqual(calls.length, 0);
});

console.log('the backup');

check('the backup is fetched with the auth header helper, never a token in the address', async () => {
  const { sandbox } = load();
  const seen = [];
  sandbox.downloadPath = async (path, name) => { seen.push([path, name]); return true; };
  await sandbox.downloadBackup();
  assert.strictEqual(seen.length, 1);
  assert.strictEqual(seen[0][0], '/api/admin/snapshot');
  assert.ok(!seen[0][0].includes('token'));
  assert.ok(/^vellum-backup-\d{8}-\d{4}\.tar$/.test(seen[0][1]), seen[0][1]);
});

Promise.all(pending).then(() => {
  if (failures) {
    console.log(`\n${failures} failed`);
    process.exit(1);
  }
  console.log('\nall passed');
});
