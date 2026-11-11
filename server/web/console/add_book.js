// The Add-book dialog.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { closeModal } from './dialogs.js';
import { loadAll } from './books.js';
import { classify, enrichBook, uploadTo } from './uploads.js';

export const AB = { results: [], file: null, proposal: null };

// ---- add / search / create (unchanged behaviour) ------------------------

// The Add-book dialog is a small editable metadata form. Attaching a file (or
// clicking "Look up online") calls /api/metadata/analyze, which parses the file
// name and runs one online search, and pre-fills the fields. Create posts the
// (possibly edited) result to from-search so authors, genres and a cover are
// stored too; a hidden AB.proposal keeps the parts with no visible field
// (cover, subjects, work key).
export function openAddBook(){
  AB.results = []; AB.file = null; AB.proposal = null;
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(640px,95vw); max-height:92vh; overflow:auto">
      <h2>Add a book</h2>
      <label>Title</label>
      <input id="ab-title" type="text" autocomplete="off" placeholder="Book title">
      <label>Author(s)</label>
      <input id="ab-authors" type="text" autocomplete="off" placeholder="Comma-separated">
      <div class="ab-grid">
        <div><label>Year</label><input id="ab-year" type="text"></div>
        <div><label>Pages</label><input id="ab-pages" type="text"></div>
        <div><label>Publisher</label><input id="ab-publisher" type="text"></div>
      </div>
      <label>ISBN</label>
      <input id="ab-isbn" type="text">
      <label>Description</label>
      <textarea id="ab-desc" rows="3"></textarea>
      <div id="ab-drop" class="ab-drop" onclick="pickAbFile()"
        ondragover="abDragOver(event)" ondragleave="abDragLeave()" ondrop="abDrop(event)">
        Drop a PDF/EPUB here, or click to choose (optional) — details fill in automatically
      </div>
      <div class="row" style="justify-content:space-between; margin-top:12px">
        <button class="btn" id="ab-lookup" onclick="runLookup()">Look up online</button>
        <div>
          <button class="btn" onclick="closeModal()">Close</button>
          <button class="btn primary" id="ab-create" onclick="createBook()">Create book</button>
        </div>
      </div>
      <div id="ab-status" class="muted" style="margin:10px 0"></div>
      <div id="ab-results" style="max-height:32vh; overflow:auto"></div>
    </div>
   </div>`;
  const t = document.getElementById('ab-title');
  t.focus();
  t.addEventListener('keydown', ev=>{ if (ev.key==='Enter'){ ev.preventDefault(); runLookup(); } });
}

export function pickAbFile(){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub';
  input.onchange = ()=>{ if (input.files[0]) setAbFile(input.files[0]); };
  input.click();
}
export async function setAbFile(file){
  const kind = await classify(file);
  if (kind !== 'pdf' && kind !== 'epub'){ toast('Only PDF or EPUB can be attached'); return; }
  AB.file = file;
  const d = document.getElementById('ab-drop');
  if (d) d.textContent = 'Attached: ' + file.name;
  await analyzeFile(file.name);
}
export function abDragOver(e){ e.preventDefault(); document.getElementById('ab-drop').classList.add('over'); }
export function abDragLeave(){ const d = document.getElementById('ab-drop'); if (d) d.classList.remove('over'); }
export function abDrop(e){ e.preventDefault(); abDragLeave(); const f = e.dataTransfer.files[0]; if (f) setAbFile(f); }

export function fillForm(r){
  AB.proposal = r || {};
  const set = (id,v)=>{ const el=document.getElementById(id); if (el) el.value = (v==null?'':v); };
  set('ab-title', r.title);
  set('ab-authors', (r.authors||[]).join(', '));
  set('ab-year', r.first_publish_year);
  set('ab-pages', r.page_count);
  set('ab-publisher', r.publisher);
  set('ab-isbn', r.isbn);
  set('ab-desc', r.description);
}

// Analyze the file name (+ one online lookup) and fill the form.
export async function analyzeFile(filename){
  const status = document.getElementById('ab-status');
  status.textContent = 'Analyzing “'+filename+'”…';
  try {
    const r = await api('POST','/api/metadata/analyze', { filename });
    fillForm(r);
    status.textContent = 'Filled from the file name and an online lookup — review, then Create.';
  } catch(e){
    const t = document.getElementById('ab-title');
    if (t && !t.value.trim()) t.value = filename.replace(/\.[^.]+$/, '');
    status.textContent = e.message;
  }
}

// Search online using whatever's typed; list matches to pick from.
export async function runLookup(){
  const status = document.getElementById('ab-status');
  const box = document.getElementById('ab-results');
  const q = document.getElementById('ab-title').value.trim()
    || document.getElementById('ab-authors').value.trim();
  if (!q){ status.textContent = 'Type a title (or attach a file) to look up.'; return; }
  status.textContent = 'Searching…'; box.innerHTML = '';
  try {
    const list = await api('GET','/api/metadata/search?q='+encodeURIComponent(q));
    AB.results = list;
    if (!list.length){ status.textContent = 'No online matches — you can still create the book from what you’ve entered.'; return; }
    status.textContent = list.length+' match'+(list.length>1?'es':'')+' — click one to fill the form.';
    box.innerHTML = list.map((r,i)=>{
      const cover = r.cover_id ? 'https://covers.openlibrary.org/b/id/'+r.cover_id+'-S.jpg' : (r.cover_url||'');
      const meta = [ (r.authors||[]).join(', '), r.first_publish_year||'' ].filter(Boolean).join(' · ');
      return '<div class="ab-item" onclick="pickCandidate('+i+')">'+
        (cover ? '<img src="'+esc(cover)+'" alt="" onerror="this.remove()">' : '<div class="ab-noimg"></div>')+
        '<div><div>'+esc(r.title)+'</div><div class="muted">'+esc(meta)+'</div></div></div>';
    }).join('');
  } catch(e){ status.textContent = e.message; }
}

export function pickCandidate(i){
  fillForm(AB.results[i]);
  document.getElementById('ab-status').textContent = 'Filled from the selected match — review, then Create.';
}

export async function createBook(){
  const title = document.getElementById('ab-title').value.trim();
  const status = document.getElementById('ab-status');
  if (!title){ status.textContent = 'Enter a title first.'; return; }
  const createBtn = document.getElementById('ab-create');
  const lookupBtn = document.getElementById('ab-lookup');
  createBtn.disabled = true; lookupBtn.disabled = true;
  createBtn.innerHTML = '<span class="spin"></span>Creating…';
  status.textContent = '';

  const yearRaw = document.getElementById('ab-year').value.trim();
  const pagesRaw = document.getElementById('ab-pages').value.trim();
  const authors = document.getElementById('ab-authors').value.split(',').map(s=>s.trim()).filter(Boolean);
  // A search-result-shaped body, so the server stores authors, genres and a
  // cover along with the plain fields; spread AB.proposal to keep the hidden
  // cover/subjects/work-key from the analyzed or selected match.
  const body = {
    ...(AB.proposal || {}),
    title,
    authors,
    publisher: document.getElementById('ab-publisher').value.trim() || null,
    isbn: document.getElementById('ab-isbn').value.trim() || null,
    description: document.getElementById('ab-desc').value.trim() || null,
    first_publish_year: yearRaw && !isNaN(parseInt(yearRaw,10)) ? parseInt(yearRaw,10) : null,
    page_count: pagesRaw && !isNaN(parseInt(pagesRaw,10)) ? parseInt(pagesRaw,10) : null,
  };
  try {
    const book = await api('POST','/api/books/from-search', body);
    if (AB.file){
      createBtn.innerHTML = '<span class="spin"></span>Uploading…';
      await uploadTo(book.id, AB.file);   // real page count + first-page cover fallback
    } else {
      createBtn.innerHTML = '<span class="spin"></span>Looking up metadata…';
      await enrichBook(book.id);          // no file: fill any gaps from the title
    }
    closeModal(); await loadAll(); toast('Created “'+title+'”');
  } catch(e){
    status.textContent = e.message;
    createBtn.disabled = false; lookupBtn.disabled = false;
    createBtn.innerHTML = 'Create book';
  }
}
