// Loading the library a page at a time, and the search/sort/filter controls.

import { S } from './state.js';
import { esc, key, toast } from './dom.js';
import { api } from './api.js';
import { render } from './table.js';

// The query string every book fetch shares, so page 1 and "Load more" can
// never disagree about what is being listed.
export function booksQuery(page){
  const p = new URLSearchParams({ page: String(page), sort: S.sort.col, dir: S.sort.dir });
  if (S.q.trim()) p.set('q', S.q.trim());
  if (S.fTag) p.set('tag', S.fTag);
  if (S.fMissing) p.set('missing', S.fMissing);
  return '/api/books?' + p.toString();
}

export async function loadAll(){
  try {
    const [page, groups, members] = await Promise.all([
      api('GET', booksQuery(1)), api('GET','/api/groups'), api('GET','/api/memberships'),
    ]);
    S.books = page.items; S.nextPage = page.next; S.total = page.total;
    S.groups = groups;
    S.members = new Set(members.map(m=>key(m.group_id,m.book_id)));
    S.selected = new Set([...S.selected].filter(id=>S.books.some(b=>b.id===id)));
    // A filter pointing at a tag that no longer exists would silently hide
    // everything; drop it rather than show an empty library.
    if (S.fTag && S.fTag !== 'untagged' && !groups.some(g=>g.id===S.fTag)) S.fTag = null;
    renderFilters(); render();
  } catch(e){ toast(e.message); }
}

// Appends the next page onto S.books (§3's paged /api/books) -- any other
// mutation reloads via loadAll() and resets back to the first page, so this
// only grows what's shown within the current session.
export async function loadMoreBooks(){
  if (S.nextPage == null) return;
  try {
    const page = await api('GET', booksQuery(S.nextPage));
    S.books = S.books.concat(page.items);
    S.nextPage = page.next; S.total = page.total;
    render();
  } catch(e){ toast(e.message); }
}

// ---- filtering + sorting (server-side since plan 5 #35) ------------------
//
// The browser no longer filters or sorts: it asks the server for the page it
// wants. `render()` therefore draws `S.books` as they arrived, and every
// control that changes the query reloads from page 1 — which is also what makes
// "no matches" trustworthy, since the old client-side filter could only ever
// say "no matches *in the pages loaded so far*".

export function computeRows(){ return S.books; }

export function reload(){ S.cursor = -1; S.nextPage = 1; S.books = []; loadAll(); }

export function sortBy(col){
  if (S.sort.col === col) S.sort.dir = S.sort.dir==='asc' ? 'desc' : 'asc';
  else S.sort = { col, dir: 'asc' };
  reload();
}

// Debounced: every keystroke is a query on the server now, not a filter over an
// array already in memory.
export let qTimer = null;
export function setQ(v){
  S.q = v;
  clearTimeout(qTimer);
  qTimer = setTimeout(reload, 250);
}

export function toggleTagFilter(id){
  S.fTag = S.fTag === id ? null : id;
  renderFilters(); reload();
}
export function toggleUntagged(){
  S.fTag = S.fTag === 'untagged' ? null : 'untagged';
  renderFilters(); reload();
}
export function toggleMissing(k){
  S.fMissing = S.fMissing === k ? null : k;
  renderFilters(); reload();
}
export function clearFilters(){
  S.q=''; document.getElementById('q').value='';
  S.fTag=null; S.fMissing=null;
  renderFilters(); reload();
}

/// Shows a label only when the thing it labels exists — an empty console
/// otherwise reads as "Tags: Views:" with nothing after either.
export function showLabelIf(id, hasContent){
  const el = document.getElementById(id);
  if (el) el.classList.toggle('hidden', !hasContent);
}

export function renderFilters(){
  document.getElementById('tagfilters').innerHTML =
    S.groups.map(g=>`<button class="fchip ${S.fTag===g.id?'on':''}" data-act="tagfilter" data-id="${esc(g.id)}">${esc(g.name)}</button>`).join('')
    + `<button class="fchip ${S.fTag==='untagged'?'on':''}" onclick="toggleUntagged()">Untagged</button>`;
  document.getElementById('missingfilters').innerHTML =
    [['file','No file'],['cover','No cover'],['year','No year'],['author','No author']]
      .map(([k,l])=>`<button class="fchip ${S.fMissing===k?'on':''}" data-act="missing" data-key="${esc(k)}">${l}</button>`).join('');
}
