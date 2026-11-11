// The book detail dialog.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api, downloadFile, hydrateImages } from './api.js';
import { ask, closeModal } from './dialogs.js';
import { loadAll } from './books.js';
import { uploadTo } from './uploads.js';

// ---- detail (unchanged) -------------------------------------------------

export function fmtSize(b){ return b>=1048576 ? (b/1048576).toFixed(1)+' MB' : Math.max(1,Math.round(b/1024))+' KB'; }

// One open detail panel's unsaved state. `pending` holds the fields a fetched
// match proposes that the panel has nowhere to type — publisher, ISBN, page
// count — so Save can write them and Cancel can drop them. `results` is the
// last search, so clicking a candidate can find it again.
export let DETAIL = { id: null, pending: null, results: [] };

export async function openDetail(id){
  let d;
  try { d = await api('GET','/api/books/'+id+'/detail'); }
  catch(e){ toast(e.message); return; }
  // A freshly opened panel has nothing unsaved, whatever the last one left.
  DETAIL = { id, pending: null, results: [], authors: (d.authors||[]).join(', ') };
  const authors = (d.authors||[]).join(', ');
  const genres = (d.genres||[]);
  const list = (d.files||[]).map(f =>
    '<div class="ab-item"><div style="flex:1">'+esc(f.format.toUpperCase())+' · '+fmtSize(f.size_bytes)+'</div>'+
    '<button class="btn" data-fid="'+esc(f.id)+'" data-fname="'+esc(d.title+'.'+f.format)+'">Download</button></div>'
  ).join('');
  const upBtn = '<button class="btn" onclick="detailPick(\''+id+'\',\'.pdf,.epub\')">Upload</button>';
  const files = list
    ? list + '<div style="text-align:right; margin-top:6px">'+upBtn+'</div>'
    : '<div style="display:flex; align-items:center; gap:10px"><span class="muted">No files uploaded.</span>'+upBtn+'</div>';
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)cancelDetail()">
    <div class="modal" style="width:min(720px,95vw); max-height:90vh; overflow:auto">
      <div style="display:flex; gap:16px">
        <div class="cover-box" data-act="detailpick" data-book="${esc(id)}" data-accept="image/*">
          <span class="hint">No cover</span>
          <img data-src="/api/books/${id}/cover?t=${Date.now()}" alt="" onerror="this.remove()">
          <div class="overlay">Change cover</div>
        </div>
        <div style="flex:1; min-width:0">
          <label>Title</label><input id="d-title" type="text" value="${esc(d.title)}">
          <label>Subtitle</label><input id="d-subtitle" type="text" value="${esc(d.subtitle||'')}">
          <label>Year</label><input id="d-year" type="text" value="${d.published_year??''}">
          <div class="muted" style="margin-top:8px">${
            [authors?('by '+esc(authors)):'', d.publisher?esc(d.publisher):'', d.isbn?('ISBN '+esc(d.isbn)):''].filter(Boolean).join(' · ')
          }</div>
          ${genres.length?('<div style="margin-top:6px">'+genres.map(g=>'<span class="chip">'+esc(g)+'</span>').join('')+'</div>'):''}
        </div>
      </div>
      <label>Description</label>
      <textarea id="d-desc" rows="5">${esc(d.description||'')}</textarea>
      <p class="muted" id="d-status" style="margin:8px 0 0; font-size:.85rem"></p>
      <div id="d-results" style="margin-top:8px"></div>
      <label>Files</label>
      ${files}
      <div class="row" style="justify-content:space-between; margin-top:16px">
        <div>
          <button class="btn danger" data-act="deletebook" data-book="${esc(id)}">Delete</button>
          <button class="btn" data-act="enrichdetail" data-book="${esc(id)}">Fetch metadata</button>
        </div>
        <div>
          <button class="btn" data-act="canceldetail">Cancel</button>
          <button class="btn primary" data-act="savedetail" data-book="${esc(id)}">Save</button>
        </div>
      </div>
    </div>
   </div>`;
  const modalRoot = document.getElementById('modal-root');
  hydrateImages(modalRoot);
  modalRoot.querySelectorAll('button[data-fid]').forEach(btn =>
    btn.onclick = () => downloadFile(btn.dataset.fid, btn.dataset.fname));
}

export function detailPick(id, accept){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = accept;
  input.onchange = async ()=>{
    if (!input.files[0]) return;
    await uploadTo(id, input.files[0]);
    openDetail(id);
  };
  input.click();
}

/// Save writes what the panel shows — the typed edits plus whatever a fetched
/// match proposed — and nothing else. Only *changed* fields go in the body: an
/// unchanged one would still bump `updated_at`, which is the clock every other
/// device pulls on.
export async function saveDetail(id){
  const body = { ...(pendingDetailEdits() || {}), ...(DETAIL.pending || {}) };
  if ('title' in body && !body.title){ toast('Title cannot be empty'); return; }
  if (!Object.keys(body).length){ closeModal(); return; }
  try { await api('PATCH','/api/books/'+id, body); closeModal(); await loadAll(); toast('Saved'); }
  catch(e){ toast(e.message); }
}

/// True while the panel holds anything that pressing Cancel would throw away.
export function detailIsDirty(){
  try { return !!(pendingDetailEdits() || DETAIL.pending); }
  catch(_){ return false; }          // panel already gone
}

/// Cancel is the way out that keeps nothing: the edits, and any fetched match
/// sitting in the form, are dropped. Confirmed only when there is something to
/// lose, so the ordinary "I just looked at it" close stays one click.
export async function cancelDetail(){
  if (detailIsDirty() && !await ask({
    title: 'Discard your changes?',
    body: 'What you have typed here will be lost.',
    confirmLabel: 'Discard',
    danger: true,
  })) return;
  DETAIL = { id: null, pending: null, results: [] };
  closeModal();
}

/// The fields edited in the detail panel but not yet saved, or null if none
/// are. `defaultValue` is what the input was rendered with, so this is a plain
/// comparison against the row as it was loaded — no separate copy to keep in
/// step.
export function pendingDetailEdits(){
  const el = id => document.getElementById(id);
  const dirty = (node, value) => node.defaultValue.trim() !== value;
  const title = el('d-title').value.trim();
  const subtitle = el('d-subtitle').value.trim();
  const desc = el('d-desc').value;
  const year = el('d-year').value.trim();

  const body = {};
  if (dirty(el('d-title'), title)) body.title = title;
  if (dirty(el('d-subtitle'), subtitle)) body.subtitle = subtitle;
  if (el('d-desc').defaultValue !== desc) body.description = desc;
  if (dirty(el('d-year'), year)) {
    const n = parseInt(year, 10);
    if (year && !isNaN(n)) body.published_year = n;
  }
  return Object.keys(body).length ? body : null;
}

// Fetch metadata proposes, it does not decide. It searches with the title as
// typed — not the one stored on the server, which is what made a rename
// invisible until you saved — and shows what it found; picking a candidate
// fills the form and *only* the form. Nothing reaches the database until Save,
// so a wrong match costs one press of Cancel rather than an edit you have to
// undo by hand.
export async function enrichFromDetail(id){
  const status = document.getElementById('d-status');
  const box = document.getElementById('d-results');
  const q = [document.getElementById('d-title').value.trim(), DETAIL.authors || '']
    .filter(Boolean).join(' ');
  if (!q){ status.textContent = 'Type a title to look up.'; return; }
  status.textContent = 'Searching…'; box.innerHTML = '';
  let list;
  try { list = await api('GET','/api/metadata/search?q='+encodeURIComponent(q)); }
  catch(e){ status.textContent = e.message; return; }
  DETAIL.results = list || [];
  if (!DETAIL.results.length){
    status.textContent = 'No online match. What is in the form is unchanged.';
    return;
  }
  status.textContent = DETAIL.results.length + ' match' +
    (DETAIL.results.length > 1 ? 'es' : '') + ' — click one to fill the form. ' +
    'Nothing is saved until you press Save.';
  box.innerHTML = DETAIL.results.map((r,i) => {
    const cover = r.cover_id
      ? 'https://covers.openlibrary.org/b/id/'+r.cover_id+'-S.jpg'
      : (r.cover_url || '');
    const meta = [(r.authors||[]).join(', '), r.first_publish_year||'', r.publisher||'']
      .filter(Boolean).join(' · ');
    return '<div class="ab-item" data-act="pickdetail" data-i="'+i+'">'+
      (cover ? '<img src="'+esc(cover)+'" alt="" onerror="this.remove()">'
             : '<div class="ab-noimg"></div>')+
      '<div><div>'+esc(r.title)+'</div><div class="muted">'+esc(meta)+'</div></div></div>';
  }).join('');
}

/// Puts a chosen match into the form. Overwrites what is there, title included
/// — the point of picking a match is that it describes the book better than
/// what you have. Publisher, ISBN and page count have nowhere to be typed, so
/// they wait in `DETAIL.pending` for Save.
export function pickDetailCandidate(i){
  const m = DETAIL.results[i];
  if (!m) return;
  const set = (id, value) => {
    const el = document.getElementById(id);
    if (el && value != null && value !== '') el.value = value;
  };
  set('d-title', m.title);
  set('d-subtitle', m.subtitle);
  set('d-year', m.first_publish_year);
  set('d-desc', m.description);

  DETAIL.pending = {};
  if (m.publisher) DETAIL.pending.publisher = m.publisher;
  if (m.isbn) DETAIL.pending.isbn = m.isbn;
  if (m.page_count) DETAIL.pending.page_count = m.page_count;
  if (!Object.keys(DETAIL.pending).length) DETAIL.pending = null;

  const extras = DETAIL.pending
    ? ' Also ready to save: ' + Object.entries(DETAIL.pending)
        .map(([k,v]) => k.replace('_',' ') + ' ' + v).join(', ') + '.'
    : '';
  document.getElementById('d-results').innerHTML = '';
  document.getElementById('d-status').textContent =
    'Filled from “' + m.title + '”. Press Save to keep it, Cancel to drop it.' + extras;
}

export async function deleteBook(id){
  if (!await ask({
    title: 'Delete this book?',
    body: 'Its files go too. This cannot be undone.',
    confirmLabel: 'Delete',
    danger: true,
  })) return;
  try { await api('DELETE','/api/books/'+id); closeModal(); await loadAll(); toast('Deleted'); }
  catch(e){ toast(e.message); }
}
