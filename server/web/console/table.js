// The books table: rendering, selection, inline editing, the selection bar.

import { OPT_COLS, S } from './state.js';
import { authorStr, bookTags, esc, toast } from './dom.js';
import { api, hydrateImages } from './api.js';
import { computeRows, loadAll } from './books.js';
import { openDetail } from './detail.js';

// ---- table --------------------------------------------------------------

export function arrow(col){ return S.sort.col===col ? (S.sort.dir==='asc'?' ▲':' ▼') : ''; }

export function headHtml(){
  const th = (col,label,w)=>
    `<th class="sortable" ${w?`style="width:${w}"`:''} data-act="sort" data-col="${esc(col)}">${label}${arrow(col)}</th>`;
  let h = '<tr><th style="width:34px"><input type="checkbox" id="selall" onchange="toggleAll(this.checked)"></th>';
  if (S.cols.has('cover'))  h += '<th style="width:44px">Cover</th>';
  h += th('title','Title');
  if (S.cols.has('author')) h += th('author','Author');
  if (S.cols.has('year'))   h += th('year','Year','70px');
  if (S.cols.has('pages'))  h += th('pages','Pages','70px');
  if (S.cols.has('status')) h += th('status','Files','90px');
  h += '<th>Tags</th>';
  if (S.cols.has('added'))  h += th('added','Added','110px');
  if (S.cols.has('owner'))  h += '<th style="width:130px">Added by</th>';
  h += '<th style="width:120px">Actions</th></tr>';
  return h;
}

export function statusCell(b){
  const f = b.file_count>0, c = !!b.cover_path;
  return `<span class="dot ${f?'on':''}" title="${f?b.file_count+' file(s)':'No file'}">●</span>${f?' '+b.file_count:''}`
       + `<span class="dot ${c?'on':''}" title="${c?'Has cover':'No cover'}" style="margin-left:8px">▣</span>`;
}

export function colCount(){ return 4 + OPT_COLS.filter(([k])=>S.cols.has(k)).length; }

export function render(){
  // The bulk-tag dropdown lives in the selection bar now, which is built below
  // — it only exists while there is a selection to act on.
  document.getElementById('thead').innerHTML = headHtml();

  S.view = computeRows();
  if (S.cursor >= S.view.length) S.cursor = -1;

  const rows = document.getElementById('rows');
  if (!S.books.length){
    rows.innerHTML = `<tr class="empty"><td colspan="${colCount()}" class="muted"
      style="text-align:center; padding:44px 14px">Your library is empty. Add your first book to get started.</td></tr>`;
  } else if (!S.view.length){
    rows.innerHTML = `<tr class="empty"><td colspan="${colCount()}" class="muted"
      style="text-align:center; padding:44px 14px">No books match the current filters.</td></tr>`;
  } else {
    rows.innerHTML = S.view.map((b,i)=>{
      const chips = bookTags(b).map(g=>
        `<span class="chip">${esc(g.name)}<button title="Remove tag" data-act="removetag" data-group="${esc(g.id)}" data-book="${esc(b.id)}">×</button></span>`
      ).join('');
      const rowCls = [S.selected.has(b.id)?'sel':'', i===S.cursor?'cursor':''].filter(Boolean).join(' ');
      let r = `<tr class="${rowCls}"
          ondragover="dragOver(event,this)" ondragleave="dragLeave(this)" data-dropbook="${esc(b.id)}"
          title="Drop a PDF/EPUB or cover image here">
        <td><input type="checkbox" ${S.selected.has(b.id)?'checked':''} data-changeact="togglerow" data-book="${esc(b.id)}"></td>`;
      if (S.cols.has('cover'))
        r += `<td>${b.cover_path
          ? `<img class="thumb" data-src="/api/books/${b.id}/cover?w=160&t=${encodeURIComponent(b.updated_at||'')}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'nothumb'}))">`
          : '<span class="nothumb"></span>'}</td>`;
      r += `<td class="title"><span class="link" data-act="titleclick" data-dblact="titleedit" data-book="${esc(b.id)}">${esc(b.title)}</span></td>`;
      if (S.cols.has('author')) r += `<td class="muted">${authorStr(b)?esc(authorStr(b)):'<span class="dim">—</span>'}</td>`;
      if (S.cols.has('year'))   r += `<td class="year editable" data-dblact="startedit" data-book="${esc(b.id)}" data-field="year">${b.published_year??''}</td>`;
      if (S.cols.has('pages'))  r += `<td class="year">${b.page_count??''}</td>`;
      if (S.cols.has('status')) r += `<td>${statusCell(b)}</td>`;
      r += `<td>${chips}<button class="addtag" data-act="quickadd" data-book="${esc(b.id)}">＋ tag</button></td>`;
      if (S.cols.has('added'))  r += `<td class="muted">${esc((b.created_at||'').slice(0,10))}</td>`;
      if (S.cols.has('owner'))  r += `<td class="muted">${b.owner_name?esc(b.owner_name):'<span class="dim">—</span>'}</td>`;
      r += `<td class="actions">
        <button class="btn sm" data-act="openreader" data-book="${esc(b.id)}">Read</button>
        <button class="btn sm" data-act="pickupload" data-book="${esc(b.id)}">Upload</button>
        <button class="btn sm" data-act="openlink" data-book="${esc(b.id)}">Link</button>
        <button class="btn sm" data-act="showcopies" data-book="${esc(b.id)}">Copies</button>
      </td></tr>`;
      return r;
    }).join('');
    hydrateImages(rows);
  }

  const selShown = S.view.filter(b=>S.selected.has(b.id)).length;
  // The header keeps the totals; the selection count moved into the bar that
  // appears with it, so it isn't said twice.
  document.getElementById('count').textContent =
    `${S.view.length} shown · ${S.total} total`;
  renderSelectionBar();
  // After the bar has been added or removed, since it changes the height.
  syncStickyHead();
  document.getElementById('selall').checked = S.view.length>0 && selShown===S.view.length;

  // Search, sort and filters run on the server since plan 5 #35, so "no
  // matches" now means no matches in the *library* rather than in the pages
  // loaded so far, and the row count below is the real one.
  const more = document.getElementById('loadmore');
  if (more){
    more.classList.toggle('hidden', S.nextPage == null);
    if (S.nextPage != null)
      more.querySelector('button').textContent = `Load more (${S.books.length} of ${S.total} loaded)`;
  }

  // keep the sticky table header parked just below the (variable-height) toolbar
  const tb = document.getElementById('topbar');
  if (tb) document.documentElement.style.setProperty('--thead-top', tb.offsetHeight+'px');
}

export function toggleRow(id, on){ on?S.selected.add(id):S.selected.delete(id); render(); }
export function toggleAll(on){ for(const b of S.view){ on?S.selected.add(b.id):S.selected.delete(b.id); } render(); }

// ---- inline editing -----------------------------------------------------

// Single click on a title opens the detail modal; a double click edits it in
// place. We defer the open briefly so a double click can cancel it.
export let clickTimer = null;
export function titleClick(id){
  if (clickTimer) return;                       // second click of a dblclick
  clickTimer = setTimeout(()=>{ clickTimer=null; openDetail(id); }, 220);
}
export function titleDbl(ev, id){
  if (clickTimer){ clearTimeout(clickTimer); clickTimer=null; }
  startEdit(ev, id, 'title');
}

export function startEdit(ev, id, field){
  const td = ev.currentTarget.closest('td');
  const b = S.books.find(x=>x.id===id);
  if (!td || !b) return;
  const cur = field==='title' ? (b.title||'') : (b.published_year??'');
  const inp = document.createElement('input');
  inp.type='text'; inp.className='celledit'; inp.value=cur;
  td.textContent=''; td.appendChild(inp); inp.focus(); inp.select();
  let closed = false;
  const finish = async (save)=>{
    if (closed) return; closed = true;
    if (save) await commitEdit(id, field, inp.value);
    render();
  };
  inp.addEventListener('keydown', e=>{
    if (e.key==='Enter'){ e.preventDefault(); finish(true); }
    else if (e.key==='Escape'){ e.preventDefault(); finish(false); }
  });
  inp.addEventListener('blur', ()=>finish(true));
}

export async function commitEdit(id, field, raw){
  const b = S.books.find(x=>x.id===id); if (!b) return;
  const v = raw.trim(), body = {};
  if (field==='title'){
    if (!v){ toast('Title cannot be empty'); return; }
    if (v===b.title) return;
    body.title = v; b.title = v;
  } else {
    if (!v){ toast('Year left unchanged (clearing isn’t supported here)'); return; }
    const y = parseInt(v,10);
    if (isNaN(y)){ toast('Year must be a number'); return; }
    if (y===b.published_year) return;
    body.published_year = y; b.published_year = y;
  }
  try { await api('PATCH','/api/books/'+id, body); toast('Saved'); }
  catch(e){ toast(e.message); loadAll(); }
}

export function afterCursorMove(){
  render();
  const el = document.querySelector('tr.cursor');
  if (el) el.scrollIntoView({ block:'nearest' });
}

/// The bar that appears when rows are selected. Rebuilt on every render so the
/// count is honest and the tag list matches the tags that currently exist.
export function renderSelectionBar(){
  const bar = document.getElementById('selbar');
  if (!bar) return;
  const n = S.selected.size;
  if (n === 0){ bar.classList.add('hidden'); bar.innerHTML = ''; return; }
  const tags = (S.groups || []).length
    ? S.groups.map(g => `<option value="${g.id}">${esc(g.name)}</option>`).join('')
    : '<option value="">(no tags yet)</option>';
  bar.classList.remove('hidden');
  bar.innerHTML = `
    <span class="count">${n} selected</span>
    <span class="sep"></span>
    <div class="group">
      <select id="bulktag">${tags}</select>
      <button class="btn sm" onclick="bulkTag(true)">Tag</button>
      <button class="btn sm" onclick="bulkTag(false)">Untag</button>
    </div>
    <span class="sep"></span>
    <button class="btn sm" onclick="openBulkEdit()">Edit</button>
    <button class="btn sm" onclick="enrichSelected()">Fetch metadata</button>
    <button class="btn sm" onclick="uploadToSelected()">Upload file</button>
    <span class="spacer"></span>
    <button class="btn sm danger" onclick="deleteSelected()">Delete</button>
    <button class="btn sm quiet" onclick="clearSelection()">Clear</button>`;
}

export function clearSelection(){ S.selected.clear(); render(); }

/// Keeps the sticky table head directly under the chrome.
///
/// It used to be a hard-coded 150px, which was fine when the toolbars were a
/// fixed stack. The chrome now grows and shrinks — the selection bar comes and
/// goes, and rows wrap on a narrow window — so the offset is measured instead
/// of guessed, or the head floats over the toolbar or leaves a gap under it.
export function syncStickyHead(){
  const bar = document.getElementById('topbar');
  if (!bar) return;
  document.documentElement.style.setProperty(
    '--thead-top', bar.getBoundingClientRect().height + 'px');
}
