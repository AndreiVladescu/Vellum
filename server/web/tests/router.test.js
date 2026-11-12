// The console's navigation: which page an address shows, and who is offered
// which pages.
//
// Two things are worth guarding. An address that names nothing — a typo, an old
// bookmark, a page this account may not open — has to land somewhere useful
// rather than on an empty screen. And the role filter may only ever *remove*
// what a member is offered: the server is the gate, and this list is a courtesy
// that must never show a member more than the console did before it existed.
//
// Run with: node web/tests/router.test.js

const vm = require('node:vm');
const assert = require('node:assert');

const source = require('./console_source.js')();

function element(id) {
  const classes = new Set(id === 'page' ? ['hidden'] : []);
  return {
    id,
    innerHTML: '',
    textContent: '',
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c),
      toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)),
    },
    hidden: () => classes.has('hidden'),
    remove() {},
    focus() { focused.push(id); },
    setAttribute() {},
    getBoundingClientRect: () => ({ height: 0, width: 0, top: 0, left: 0 }),
    querySelector: () => element('inner'),
    querySelectorAll: () => [],
    appendChild() {},
    addEventListener() {},
    value: '',
  };
}

let focused = [];

function load({ hash = '', master = null } = {}) {
  focused = [];
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  const replaced = [];
  const stored = master === null ? {} : { vellum_master: master ? '1' : '0' };
  const sandbox = {
    document: {
      getElementById: get,
      querySelector: (sel) => (sel === '#page .pagehead h2' ? element('page-heading') : null),
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
    location: { hash },
    history: {
      replaceState: (_s, _t, url) => { replaced.push(url); sandbox.location.hash = url; },
    },
    localStorage: { getItem: () => null, setItem: () => {} },
    sessionStorage: {
      getItem: (k) => (k in stored ? stored[k] : null),
      setItem: (k, v) => { stored[k] = v; },
      removeItem: (k) => { delete stored[k]; },
    },
    fetch: () => Promise.reject(new Error('no network in this test')),
    crypto: {},
    console,
    setTimeout,
    clearTimeout,
    URL,
    Blob: class {},
    addEventListener: () => {},
    matchMedia: () => ({ matches: false, addEventListener: () => {} }),
    requestAnimationFrame: () => {},
    scrollTo: () => {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  return { sandbox, get, replaced, stored };
}

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

/// What the old Manage menu offered a member, as a list of page names. The
/// four master-only ones are the ones whose endpoints answer 403 to anyone
/// else; the role filter may take those away and nothing more.
const MASTER_ONLY = ['/lending/reminders', '/people/users', '/server/about', '/server/activity'];

async function main() {
  const { sandbox } = load();
  const { routePath, resolveRoute, navHtml } = sandbox;
  // Top-level consts are not properties of the context's global object, so
  // they are read out by evaluating their names in it.
  const { ROUTES, NAV_GROUPS, NAV_ACTIONS, HOME, ACTIONS } =
    vm.runInContext('({ ROUTES, NAV_GROUPS, NAV_ACTIONS, HOME, ACTIONS })', sandbox);

  console.log('route parsing');

  await check('a hash reads as its path', () => {
    assert.strictEqual(routePath('#/lending/loans'), '/lending/loans');
  });
  await check('a trailing slash and capitals do not make a different page', () => {
    assert.strictEqual(routePath('#/Lending/Loans/'), '/lending/loans');
  });
  await check('anything that is not #/… is no path at all', () => {
    for (const h of ['', '#', '#top', 'lending/loans', null, undefined]) {
      assert.strictEqual(routePath(h), '', String(h));
    }
  });

  console.log('\nresolving');

  await check('every listed page resolves to itself, unredirected, for the master', () => {
    for (const r of ROUTES) {
      const out = resolveRoute('#' + r.path, true);
      assert.strictEqual(out.route.path, r.path);
      assert.strictEqual(out.redirect, false, r.path);
    }
  });
  await check('an unknown address falls back to the books, and says so', () => {
    const out = resolveRoute('#/library/nope', true);
    assert.strictEqual(out.route.path, HOME);
    assert.strictEqual(out.redirect, true);
  });
  await check('no address at all is the books', () => {
    const out = resolveRoute('', false);
    assert.strictEqual(out.route.path, '/library/books');
    assert.strictEqual(out.redirect, true, 'so the address bar shows where you are');
  });
  await check('a differently-spelled address is corrected to the canonical one', () => {
    const out = resolveRoute('#/People/Shares/', false);
    assert.strictEqual(out.route.path, '/people/shares');
    assert.strictEqual(out.redirect, true);
  });
  await check('a member asking for a master page gets the books instead', () => {
    for (const p of MASTER_ONLY) {
      const out = resolveRoute('#' + p, false);
      assert.strictEqual(out.route.path, HOME, p);
      assert.strictEqual(out.redirect, true, p);
    }
  });
  await check('an unknown role is offered everything, as before, and the server decides', () => {
    for (const p of MASTER_ONLY) {
      assert.strictEqual(resolveRoute('#' + p, null).route.path, p);
    }
  });

  console.log('\nthe nav');

  await check('every page sits in exactly one of the four groups, under its own prefix', () => {
    assert.deepEqual(NAV_GROUPS.map((g) => g.id), ['library', 'lending', 'people', 'server']);
    for (const r of ROUTES) {
      assert.ok(NAV_GROUPS.some((g) => g.id === r.group), r.path);
      assert.ok(r.path.startsWith('/' + r.group + '/'), r.path);
    }
    assert.strictEqual(new Set(ROUTES.map((r) => r.path)).size, ROUTES.length, 'no duplicates');
  });
  await check('the master-only pages are exactly the ones the server refuses a member', () => {
    assert.deepEqual(ROUTES.filter((r) => r.master).map((r) => r.path).sort(), [...MASTER_ONLY].sort());
  });
  await check('the current page, and only it, carries aria-current', () => {
    const html = navHtml('/lending/loans', true);
    assert.strictEqual((html.match(/aria-current="page"/g) || []).length, 1);
    assert.ok(/href="#\/lending\/loans" aria-current="page"/.test(html));
  });
  await check('a member is not offered the master pages or the email setup', () => {
    const html = navHtml(HOME, false);
    for (const p of MASTER_ONLY) assert.ok(!html.includes('#' + p), p);
    assert.ok(!html.includes('data-id="mail"'));
    for (const r of ROUTES.filter((x) => !x.master)) assert.ok(html.includes('#' + r.path), r.path);
  });
  await check('the master is offered every page and every action', () => {
    const html = navHtml(HOME, true);
    for (const r of ROUTES) assert.ok(html.includes('href="#' + r.path + '"'), r.path);
    for (const a of NAV_ACTIONS) assert.ok(html.includes('data-id="' + a.id + '"'), a.id);
  });
  await check('nav actions go through the delegated table, not an inline handler', () => {
    assert.ok(!/onclick=/.test(navHtml(HOME, true)));
    assert.strictEqual(typeof ACTIONS.navaction, 'function');
  });

  console.log('\nrendering a route');

  await check('the role a sign-in answered with is remembered for the tab', () => {
    const { sandbox: sb, stored } = load();
    sb.rememberRole({ email: 'a@b', is_master: false });
    assert.strictEqual(stored.vellum_master, '0');
    assert.strictEqual(vm.runInContext('S.isMaster', sb), false);
    sb.rememberRole(null);
    assert.ok(!('vellum_master' in stored), 'signing out forgets it');
    assert.strictEqual(vm.runInContext('S.isMaster', sb), null);
  });
  await check('a stored role is read back on reload', () => {
    const { sandbox: sb } = load({ master: true });
    assert.strictEqual(vm.runInContext('S.isMaster', sb), true);
  });
  await check('an unknown address is replaced, not pushed, so Back does not bounce', async () => {
    const { sandbox: sb, replaced } = load({ hash: '#/nowhere', master: true });
    await sb.renderRoute();
    assert.deepEqual(replaced, ['#/library/books']);
  });
  await check('a page whose loader refuses falls back to the books', async () => {
    // A 403 from the server's numbers: showServer toasts and opens nothing.
    const { sandbox: sb, replaced, get } = load({ hash: '#/server/about', master: true });
    sb.fetch = async () => ({ status: 403, ok: false, json: async () => ({ error: 'master only' }) });
    await sb.renderRoute();
    assert.deepEqual(replaced, ['#/library/books']);
    assert.strictEqual(get('page').hidden(), true, 'the books are what is on screen');
  });
  await check('the old statistics address opens the Server page and is corrected to it', async () => {
    const { sandbox: sb, replaced } = load({ hash: '#/server/stats', master: true });
    sb.fetch = async () => ({ status: 200, ok: true, json: async () => ({}) });
    await sb.renderRoute();
    assert.deepEqual(replaced, ['#/server/about']);
  });
  await check('a member asking for the old statistics address lands on the books', () => {
    const { sandbox: sb } = load({ master: false });
    const r = sb.resolveRoute('#/server/stats', false);
    assert.strictEqual(r.route.path, '/library/books');
    assert.strictEqual(r.redirect, true);
  });
  await check('the overview is for everyone and is the first item of the nav', () => {
    const { sandbox: sb } = load({ master: false });
    const html = sb.navHtml('/library/overview', false);
    assert.ok(html.indexOf('#/library/overview') < html.indexOf('#/library/books'));
    assert.ok(html.includes('aria-current="page">Overview'));
    assert.ok(!html.includes('/server/about'), 'the Server page is the owner\'s');
  });
  await check('a page that opens keeps its address and takes focus at its heading', async () => {
    const { sandbox: sb, replaced, get } = load({ hash: '#/lending/loans', master: false });
    sb.fetch = async () => ({ status: 200, ok: true, json: async () => [] });
    await sb.renderRoute();
    assert.deepEqual(replaced, []);
    assert.strictEqual(get('page').hidden(), false);
    assert.ok(focused.includes('page-heading'), 'focus moved to the page heading');
  });
  await check('the books route focuses the books heading', async () => {
    const { sandbox: sb } = load({ hash: '#/library/books', master: false });
    await sb.renderRoute();
    assert.ok(focused.includes('books-heading'));
  });

  if (failures) {
    console.log(`\n${failures} failing`);
    process.exit(1);
  }
  console.log('\nall passed');
}

main();
