// Navigation: four groups of pages, each page at its own `#/group/page` address.
//
// Hash routes rather than real paths because the server serves the console at
// `/` and nothing else: a hash never reaches the server, so reload, back/forward
// and bookmarks work without a catch-all route there. The address is the source
// of truth — a nav link only changes the hash, and `renderRoute()` draws
// whatever the hash says — so the view and the URL cannot disagree.
//
// Role filtering here is a courtesy, not a gate: the server answers 403 to a
// member whatever the console shows. Its one job is to leave out what a member
// could only ever be refused, and never to show a member more than before.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { closePage, pageOpen, pageOpens } from './pages.js';
import { loadAll } from './books.js';
import { openImport } from './import.js';
import { createTag } from './tags.js';
import { showLoans } from './loans.js';
import { showRequests } from './requests.js';
import { showReminders } from './reminders.js';
import { showPeople } from './people.js';
import { showShares } from './shares.js';
import { showRooms } from './rooms.js';
import { showStats } from './stats.js';
import { showOverview } from './overview.js';
import { showActivity } from './activity.js';
import { showCert } from './cert.js';
import { showMailSetup } from './mail.js';

export const NAV_GROUPS = [
  { id: 'library', label: 'Library' },
  { id: 'lending', label: 'Lending' },
  { id: 'people', label: 'People and sharing' },
  { id: 'server', label: 'Server' },
];

export const HOME = '/library/books';

/// Every page with an address. `master: true` marks the ones whose endpoints
/// answer 403 to anyone else — the same pages that used to toast "Only the
/// library owner can…" when a member opened them.
export const ROUTES = [
  // Beside the books, not in place of them: the books table is the working
  // surface and what every bookmark and habit points at. The overview is one
  // click away, first in the nav.
  { path: '/library/overview', group: 'library', label: 'Overview', show: () => showOverview() },
  { path: '/library/books', group: 'library', label: 'Books' },
  { path: '/lending/loans', group: 'lending', label: 'Loans', show: () => showLoans() },
  { path: '/lending/requests', group: 'lending', label: 'Borrow requests', show: () => showRequests() },
  { path: '/lending/reminders', group: 'lending', label: 'Due-date reminders', master: true,
    show: () => showReminders() },
  { path: '/people/users', group: 'people', label: 'People', master: true, show: () => showPeople() },
  { path: '/people/shares', group: 'people', label: 'Shares and links', show: () => showShares() },
  { path: '/people/rooms', group: 'people', label: 'Rooms', show: () => showRooms() },
  { path: '/server/stats', group: 'server', label: 'Statistics', master: true, show: () => showStats() },
  { path: '/server/activity', group: 'server', label: 'Activity log', master: true,
    show: () => showActivity() },
];

/// Dialogs reachable from the nav. They ask a question on top of a page rather
/// than being one, so they get no address: reloading into a half-filled import
/// is not something anyone wants to bookmark.
export const NAV_ACTIONS = [
  { id: 'import', group: 'library', label: 'Import books…', run: () => openImport() },
  { id: 'newtag', group: 'library', label: 'New tag…', run: () => createTag() },
  { id: 'cert', group: 'server', label: 'Certificate', run: () => showCert() },
  { id: 'mail', group: 'server', label: 'Email setup', master: true, run: () => showMailSetup() },
];

/// `isMaster` is true, false, or null when unknown (a session from before the
/// role was remembered). Unknown shows everything, as the console always did,
/// and leaves the refusing to the server.
export function allowed(item, isMaster){
  return !item.master || isMaster !== false;
}

/// The path in a location hash: `#/lending/loans/` → `/lending/loans`. Anything
/// that is not a `#/…` path reads as no path at all.
export function routePath(hash){
  const h = String(hash || '').replace(/^#/, '');
  if (!h.startsWith('/')) return '';
  return h.replace(/\/+$/, '').toLowerCase();
}

/// Which page a hash shows, and whether the address has to be corrected to say
/// so. An unknown address, or one this account may not open, falls back to the
/// books — the one page every account has — rather than to an empty screen.
export function resolveRoute(hash, isMaster){
  const path = routePath(hash);
  const route = ROUTES.find(r => r.path === path);
  if (route && allowed(route, isMaster)) {
    return { route, redirect: '#' + route.path !== String(hash || '') };
  }
  return { route: ROUTES.find(r => r.path === HOME), redirect: true };
}

/// The nav's markup for one account, with the current page marked.
export function navHtml(current, isMaster){
  return NAV_GROUPS.map(g => {
    const links = ROUTES.filter(r => r.group === g.id && allowed(r, isMaster)).map(r =>
      `<li><a href="#${r.path}"${r.path === current ? ' aria-current="page"' : ''}>${esc(r.label)}</a></li>`);
    const acts = NAV_ACTIONS.filter(a => a.group === g.id && allowed(a, isMaster)).map(a =>
      `<li><button type="button" class="nav-act" data-act="navaction" data-id="${esc(a.id)}">${esc(a.label)}</button></li>`);
    const items = links.concat(acts);
    if (!items.length) return '';
    return `<div class="nav-group">
      <p class="nav-label" id="ng-${g.id}">${esc(g.label)}</p>
      <ul aria-labelledby="ng-${g.id}">${items.join('')}</ul>
    </div>`;
  }).join('');
}

// ---- the browser side ---------------------------------------------------

let routeSeq = 0;
let listening = false;

/// Sets the address. A change of hash fires `hashchange`, which draws the page;
/// so does following a nav link, which is why the links are plain `href`s.
export function go(path){
  if (location.hash === '#' + path) renderRoute();
  else location.hash = '#' + path;
}

/// Draws the page the address names. `focus` is false for a refresh in place,
/// which should not move the reader's focus.
export async function renderRoute(focus = true){
  const seq = ++routeSeq;
  const { route, redirect } = resolveRoute(location.hash, S.isMaster);
  // replaceState, not `location.hash =`: a corrected address must not leave the
  // wrong one behind it in history, or Back lands on it and bounces again.
  if (redirect) history.replaceState(null, '', '#' + route.path);
  renderNav(route.path);
  closeNav(false);

  if (!route.show){
    if (pageOpen()) closePage();
    if (focus) focusHeading();
    return;
  }
  const before = pageOpens();
  await route.show();
  if (seq !== routeSeq) return;                 // the reader has moved on
  // The loader shows a toast and opens nothing when the server refuses — a
  // member on a stale role, say. Stay where the screen actually is.
  if (pageOpens() === before){
    history.replaceState(null, '', '#' + HOME);
    renderNav(HOME);
    if (pageOpen()) closePage();
    if (focus) focusHeading();
    return;
  }
  if (focus) focusHeading();
}

/// Re-runs the current page's loader: the library for the books, the page's
/// own fetch for the rest.
export function refresh(){
  const { route } = resolveRoute(location.hash, S.isMaster);
  if (!route.show) loadAll();
  else renderRoute(false);
}

/// Called once signed in. Draws whatever the address names — which is how a
/// bookmark to a page survives having to sign in first.
export function startRouter(){
  if (!listening){
    window.addEventListener('hashchange', () => renderRoute());
    listening = true;
  }
  renderRoute();
}

export function runNavAction(id){
  const a = NAV_ACTIONS.find(x => x.id === id);
  if (!a) return;
  if (!allowed(a, S.isMaster)) { toast('Only the library owner can do that.'); return; }
  closeNav(false);
  a.run();
}

function renderNav(current){
  const host = document.getElementById('nav-groups');
  if (host) host.innerHTML = navHtml(current, S.isMaster);
  const label = document.getElementById('nav-current');
  const route = ROUTES.find(r => r.path === current);
  if (label && route) label.textContent = route.label;
}

/// Moves focus to the page's heading, so a screen reader announces where a
/// route change landed and Tab continues from the top of the new page.
function focusHeading(){
  const h = pageOpen()
    ? document.querySelector('#page .pagehead h2')
    : document.getElementById('books-heading');
  if (h && h.focus) h.focus({ preventScroll: true });
}

// ---- the collapsed nav (narrow screens) -----------------------------------

export function navOpen(){
  const nav = document.getElementById('nav');
  return !!(nav && nav.classList.contains('open'));
}

export function toggleNav(){
  if (navOpen()) closeNav(true);
  else {
    document.getElementById('nav').classList.add('open');
    document.getElementById('nav-toggle').setAttribute('aria-expanded', 'true');
    const first = document.querySelector('#nav-groups a, #nav-groups button');
    if (first) first.focus();
  }
}

/// `refocus` returns focus to the toggle — for Escape, so keyboard focus is not
/// left inside a list that just disappeared.
export function closeNav(refocus){
  const nav = document.getElementById('nav');
  if (!nav || !nav.classList.contains('open')) return;
  nav.classList.remove('open');
  const toggle = document.getElementById('nav-toggle');
  toggle.setAttribute('aria-expanded', 'false');
  if (refocus) toggle.focus();
}
