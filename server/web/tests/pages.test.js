// Shares, People and Borrow requests open as pages, not boxes on top.
//
// The risk in the change is not how a page looks — it is what happens to the
// library underneath. A page that forgets to hide the table leaves two lists on
// screen; one that forgets to bring it back leaves the console empty after
// Escape. Both are asserted here.
//
// Run with: node web/tests/pages.test.js

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

function load() {
  const els = new Map();
  const get = (id) => {
    if (!els.has(id)) els.set(id, element(id));
    return els.get(id);
  };
  // The two filter/search bars the library owns.
  const toolbars = [element('bar1'), element('bar2')];
  const sandbox = {
    document: {
      getElementById: get,
      querySelectorAll: (selector) =>
        selector === '#topbar .toolbar' ? toolbars : [],
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
    addEventListener: () => {},
    matchMedia: () => ({ matches: false, addEventListener: () => {} }),
    requestAnimationFrame: () => {},
    scrollTo: () => {},
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  return { sandbox, get, toolbars };
}

let failures = 0;
function check(name, fn) {
  try {
    fn();
    console.log('  ok   ' + name);
  } catch (e) {
    failures++;
    console.log('  FAIL ' + name + '\n       ' + e.message);
  }
}

console.log('openPage / closePage');

check('a page hides the library table and its controls', () => {
  const { sandbox, get, toolbars } = load();
  sandbox.openPage('Shares', 'what went out', '<div>rows</div>');

  assert.strictEqual(get('page').hidden(), false, 'the page is on screen');
  assert.strictEqual(get('tbl').hidden(), true, 'the book table is not');
  assert.strictEqual(get('loadmore').hidden(), true);
  for (const bar of toolbars) {
    assert.strictEqual(bar.hidden(), true, 'search and filters go with it');
  }
});

check('the heading and the line under it are the ones passed in', () => {
  const { sandbox, get } = load();
  sandbox.openPage('Borrow requests', 'Approving creates the loan', '<i>rows</i>');
  const html = get('page').innerHTML;
  assert.ok(html.includes('Borrow requests'), 'the title');
  assert.ok(html.includes('Approving creates the loan'), 'the subtitle');
  assert.ok(html.includes('<i>rows</i>'), 'the body, unescaped — it is markup');
  assert.ok(html.includes('← Library'), 'and the way back');
});

check('a title with markup in it is escaped', () => {
  const { sandbox, get } = load();
  sandbox.openPage('<img src=x onerror=alert(1)>', '', '');
  assert.ok(!get('page').innerHTML.includes('<img'), 'escaped, not rendered');
});

check('closing brings the library back and empties the page', () => {
  const { sandbox, get, toolbars } = load();
  sandbox.openPage('Shares', '', '<div>rows</div>');
  sandbox.closePage();

  assert.strictEqual(get('page').hidden(), true);
  assert.strictEqual(get('page').innerHTML, '', 'nothing left rendering underneath');
  assert.strictEqual(get('tbl').hidden(), false, 'the table is back');
  for (const bar of toolbars) {
    assert.strictEqual(bar.hidden(), false, 'and so are its controls');
  }
});

check('pageOpen reports which of the two is on screen', () => {
  const { sandbox } = load();
  assert.strictEqual(sandbox.pageOpen(), false, 'the library, to start');
  sandbox.openPage('Shares', '', '');
  assert.strictEqual(sandbox.pageOpen(), true);
  sandbox.closePage();
  assert.strictEqual(sandbox.pageOpen(), false);
});

if (failures) {
  console.log(`\n${failures} failing`);
  process.exit(1);
}
console.log('\nall passed');
