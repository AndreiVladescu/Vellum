// The import wizard: a catalogue file or a folder of books, reviewed first.

import { esc, key, toast } from './dom.js';
import { api } from './api.js';
import { closeModal } from './dialogs.js';
import { loadAll } from './books.js';
import { xhrUpload } from './uploads.js';

export const IMP = { items: [] };

// ---- import wizard ------------------------------------------------------
//
// Two sources, one review screen (next features #5). The screen is the point:
// the app's folder import has shown you what it *would* do since plan 5 #15,
// and an importer that writes first and reports afterwards is how a library
// ends up with forty duplicates you then have to find.
//
// The duplicate check is `POST /api/import/check`, deliberately server-side —
// the app checks the same way, so the same catalogue imported from the browser
// and from the phone reaches the same verdict. The old version of this dialog
// compared titles in JavaScript against whatever books happened to be loaded,
// which is how it managed to miss duplicates past the first page.

export function openImport(){
  IMP.items = [];
  IMP.source = 'catalogue';
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(900px,96vw)">
      <h2>Import books</h2>
      <div class="row" style="justify-content:flex-start; gap:8px; margin-bottom:10px">
        <button class="btn" id="imp-tab-cat" onclick="importSource('catalogue')">A catalogue file</button>
        <button class="btn" id="imp-tab-folder" onclick="importSource('folder')">A folder of books</button>
      </div>
      <div id="imp-source"></div>
      <div id="imp-status" class="muted" style="margin:8px 0; min-height:1.2em"></div>
      <div id="imp-review" style="max-height:44vh; overflow:auto"></div>
      <div class="row" style="margin-top:10px">
        <button class="btn" onclick="closeModal()">Close</button>
        <button class="btn primary" id="imp-do" disabled onclick="importDo()">Import</button>
      </div>
    </div>
   </div>`;
  importSource('catalogue');
}

export function importSource(which){
  IMP.source = which;
  IMP.items = [];
  document.getElementById('imp-review').innerHTML = '';
  document.getElementById('imp-status').textContent = '';
  document.getElementById('imp-do').disabled = true;
  for (const [id, name] of [['imp-tab-cat','catalogue'], ['imp-tab-folder','folder']]){
    document.getElementById(id).classList.toggle('primary', which === name);
  }
  document.getElementById('imp-source').innerHTML = which === 'catalogue'
    ? `<p class="muted">CSV or JSON. For CSV the first row is the header and a
         <b>title</b> column is required; <b>authors, subtitle, year, publisher,
         isbn, pages</b> are optional. Aliases a Goodreads or StoryGraph export
         already uses are understood.</p>
       <textarea id="imp-text" rows="6" placeholder="title,authors,year
The Odyssey,Homer,1996"></textarea>
       <div class="row" style="justify-content:flex-start; margin-top:8px">
         <button class="btn" onclick="importPickFile()">Choose a file…</button>
         <button class="btn" onclick="importScan()">Review</button>
       </div>`
    : `<p class="muted">Pick a folder of PDFs and EPUBs. Names like
         <b>Author - Title (Year).epub</b> are read for their metadata; anything
         else keeps its file name as the title. Files are hashed in the browser,
         so a book already on the server is recognised by its contents rather
         than its name.</p>
       <div class="row" style="justify-content:flex-start">
         <button class="btn" onclick="importPickFolder()">Choose a folder…</button>
       </div>`;
}

export function importPickFile(){
  const i = document.createElement('input');
  i.type='file'; i.accept='.csv,.json,.txt,text/csv,application/json,text/plain';
  i.onchange = async ()=>{ const f=i.files[0]; if(!f) return;
    document.getElementById('imp-text').value = await f.text(); importScan(); };
  i.click();
}

export function importPickFolder(){
  const i = document.createElement('input');
  i.type='file'; i.multiple = true; i.webkitdirectory = true;
  i.onchange = ()=> importScanFolder([...i.files]);
  i.click();
}

// A small CSV parser: handles quoted cells, escaped "" quotes, and \r\n.
export function parseCSV(text){
  const rows=[]; let row=[], cell='', q=false;
  for (let i=0;i<text.length;i++){
    const c=text[i];
    if (q){
      if (c==='"'){ if (text[i+1]==='"'){ cell+='"'; i++; } else q=false; }
      else cell+=c;
    } else {
      if (c==='"') q=true;
      else if (c===','){ row.push(cell); cell=''; }
      else if (c==='\n'){ row.push(cell); rows.push(row); row=[]; cell=''; }
      else if (c!=='\r') cell+=c;
    }
  }
  if (cell.length || row.length){ row.push(cell); rows.push(row); }
  return rows.filter(r=>r.some(x=>x.trim()!==''));
}

// The column aliases a real export actually uses, so a Goodreads or StoryGraph
// file imports without being edited first. Same list the app understands
// (docs/IMPORTING.md).
export const IMP_COLS = {
  title:     ['title','name','book title'],
  subtitle:  ['subtitle'],
  authors:   ['author','authors','primary author'],
  year:      ['year','published_year','published','original publication year','first published'],
  publisher: ['publisher'],
  isbn:      ['isbn','isbn13','isbn_13','isbn/uid'],
  pages:     ['pages','page_count','number of pages'],
};

export function splitAuthors(raw){
  return String(raw||'').split(/[;,]|\band\b|&/).map(s=>s.trim()).filter(Boolean);
}

export function parseCatalogue(text){
  const trimmed = text.trim();
  if (!trimmed) return { error:'Nothing to read yet.' };

  // JSON first: a bare array, or {books:[...]} / {items:[...]}.
  if (trimmed[0] === '[' || trimmed[0] === '{'){
    let data;
    try { data = JSON.parse(trimmed); }
    catch(e){ return { error:'That is not valid JSON: '+e.message }; }
    const list = Array.isArray(data) ? data : (data.books || data.items);
    if (!Array.isArray(list)) return { error:'JSON needs to be an array of books.' };
    const items = [];
    for (const raw of list){
      const title = String(raw.title || raw.name || '').trim();
      if (!title) continue;
      items.push({
        title,
        subtitle: raw.subtitle || null,
        authors: Array.isArray(raw.authors) ? raw.authors : splitAuthors(raw.authors || raw.author),
        publisher: raw.publisher || null,
        isbn: raw.isbn || null,
        published_year: Number.isFinite(+raw.year) ? +raw.year : (Number.isFinite(+raw.published_year) ? +raw.published_year : null),
        page_count: Number.isFinite(+raw.pages) ? +raw.pages : (Number.isFinite(+raw.page_count) ? +raw.page_count : null),
      });
    }
    return items.length ? { items } : { error:'No rows with a title.' };
  }

  const rows = parseCSV(trimmed);
  if (!rows.length) return { error:'Nothing to parse.' };
  const header = rows[0].map(h=>h.trim().toLowerCase());
  const idx = names=>{ for(const n of names){ const i=header.indexOf(n); if(i>=0) return i; } return -1; };
  const at = {};
  for (const [field, names] of Object.entries(IMP_COLS)) at[field] = idx(names);
  if (at.title < 0) return { error:'The first row needs a "title" column.' };

  const items = [];
  for (let r=1;r<rows.length;r++){
    const row = rows[r];
    const title = (row[at.title]||'').trim();
    if (!title) continue;
    const num = i => { if (i<0 || !row[i]) return null; const n = parseInt(row[i],10); return isNaN(n) ? null : n; };
    items.push({
      title,
      subtitle: at.subtitle>=0 ? (row[at.subtitle]||'').trim() || null : null,
      authors: at.authors>=0 ? splitAuthors(row[at.authors]) : [],
      publisher: at.publisher>=0 ? (row[at.publisher]||'').trim() || null : null,
      isbn: at.isbn>=0 ? (row[at.isbn]||'').trim() || null : null,
      published_year: num(at.year),
      page_count: num(at.pages),
    });
  }
  return items.length ? { items } : { error:'No rows with a title.' };
}

// `Author - Title (Year).epub`, falling back to the bare file name. Same shape
// the app's filename reader accepts.
export function fromFilename(name){
  const stem = name.replace(/\.[^.]+$/, '');
  let year = null;
  let rest = stem.replace(/\((\d{4})\)\s*$/, (_, y)=>{ year = +y; return ''; }).trim();
  let authors = [];
  const dash = rest.split(/\s+-\s+/);
  if (dash.length >= 2){
    authors = splitAuthors(dash[0]);
    rest = dash.slice(1).join(' - ');
  }
  return { title: rest.trim() || stem, authors, published_year: year };
}

export async function sha256Of(file){
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

export async function importScan(){
  const st = document.getElementById('imp-status');
  const parsed = parseCatalogue(document.getElementById('imp-text').value);
  if (parsed.error){ st.textContent = parsed.error; return; }
  st.textContent = 'Checking '+parsed.items.length+' row(s) against your library…';
  await importReview(parsed.items);
}

export async function importScanFolder(files){
  const st = document.getElementById('imp-status');
  const books = files.filter(f=>/\.(pdf|epub)$/i.test(f.name));
  if (!books.length){ st.textContent = 'No PDF or EPUB files in that folder.'; return; }
  const items = [];
  for (let i=0;i<books.length;i++){
    const f = books[i];
    st.textContent = `Hashing ${i+1} of ${books.length}…`;
    items.push({ ...fromFilename(f.name), file: f, sha256: await sha256Of(f) });
  }
  st.textContent = 'Checking '+items.length+' file(s) against your library…';
  await importReview(items);
}

/// Asks the server what each row collides with, then draws the review table.
export async function importReview(items){
  const st = document.getElementById('imp-status');
  let verdicts = [];
  try {
    verdicts = await api('POST','/api/import/check', {
      candidates: items.map((it, i)=>({
        key: String(i),
        title: it.title,
        isbn: it.isbn || null,
        authors: it.authors || [],
        sha256: it.sha256 || null,
      })),
    });
  } catch(e){
    // An older server has no check endpoint. Import is still possible; it just
    // cannot warn, and saying so is better than pretending everything is new.
    st.textContent = 'Could not check for duplicates ('+e.message+') — review carefully.';
  }
  const byKey = new Map(verdicts.map(v=>[v.key, v]));
  IMP.items = items.map((it, i)=>{
    const v = byKey.get(String(i)) || {};
    // Certain duplicates start unticked; a title match is only a suggestion, so
    // it stays ticked and merely says why.
    return { ...it, verdict: v, include: !v.certain };
  });
  const dupes = IMP.items.filter(x=>x.verdict.reason).length;
  st.textContent = `${items.length} row(s) read`
    + (dupes ? `, ${dupes} look like books you already have` : ', none look familiar')
    + '. Nothing is written until you press Import.';
  importRenderReview();
}

export function importRenderReview(){
  const rows = IMP.items.map((it, i)=>{
    const v = it.verdict || {};
    const why = !v.reason ? '<span class="muted">new</span>'
      : v.reason === 'same_file' ? `<b>same file</b> as “${esc(v.title)}”`
      : v.reason === 'same_isbn' ? `<b>same ISBN</b> as “${esc(v.title)}”`
      : `looks like “${esc(v.title)}”`;
    return `<tr>
      <td><input type="checkbox" ${it.include?'checked':''} data-changeact="importtoggle" data-index="${i}"></td>
      <td class="title">${esc(it.title)}</td>
      <td>${esc((it.authors||[]).join(', '))}</td>
      <td>${it.file ? esc(it.file.name) : ''}</td>
      <td>${why}</td>
    </tr>`;
  }).join('');
  document.getElementById('imp-review').innerHTML = `
    <table>
      <thead><tr><th></th><th>Title</th><th>Author</th><th>File</th><th>Already here?</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
  importCount();
}

export function importToggle(i, on){ IMP.items[i].include = on; importCount(); }

export function importCount(){
  const n = IMP.items.filter(x=>x.include).length;
  const btn = document.getElementById('imp-do');
  btn.disabled = n === 0;
  btn.textContent = n ? 'Import '+n : 'Import';
}

export async function importDo(){
  const chosen = IMP.items.filter(x=>x.include);
  if (!chosen.length) return;
  const btn = document.getElementById('imp-do');
  const st = document.getElementById('imp-status');
  btn.disabled = true;
  let ok = 0, failed = 0;
  for (let i=0;i<chosen.length;i++){
    const it = chosen[i];
    btn.innerHTML = '<span class="spin"></span>Importing '+(i+1)+' of '+chosen.length+'…';
    try {
      // from-search rather than /books: it is the endpoint that stores authors
      // and genres alongside the plain fields.
      const book = await api('POST','/api/books/from-search', {
        title: it.title,
        subtitle: it.subtitle || null,
        authors: it.authors || [],
        publisher: it.publisher || null,
        isbn: it.isbn || null,
        first_publish_year: it.published_year || null,
        page_count: it.page_count || null,
      });
      if (it.file) await xhrUpload('POST','/api/books/'+book.id+'/files?filename='+encodeURIComponent(it.file.name), it.file, it.file.type || 'application/octet-stream');
      ok++;
    } catch(e){ failed++; st.textContent = 'Last error: '+e.message; }
  }
  closeModal();
  await loadAll();
  toast('Imported '+ok+(failed?', '+failed+' failed':''));
}
