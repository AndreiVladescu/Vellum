const S = { token: localStorage.getItem('vellum_token'), email: localStorage.getItem('vellum_email'),
            books: [], groups: [], members: new Set(), selected: new Set(),
            view: [], cursor: -1,
            // /api/books?page=1 (§3) loads the library a page at a time instead
            // of unbounded; nextPage is the next page to fetch via "Load more",
            // null once every book is loaded. total is the server's count of
            // every visible book, independent of how many pages are in S.books.
            nextPage: 1, total: 0,
            q: '', sort: { col: 'title', dir: 'asc' },
            fTags: new Set(), fUntagged: false, fMissing: new Set(),
            cols: new Set(JSON.parse(localStorage.getItem('vellum_cols') || 'null') || ['author','year','status']),
            compact: localStorage.getItem('vellum_density') === '1' };
const AB = { results: [], file: null, proposal: null };
const IMP = { items: [] };

// Columns the user can show or hide (the checkbox, title, tags and actions
// columns are always present).
const OPT_COLS = [['cover','Cover thumbnail'],['author','Author'],['year','Year'],
                  ['pages','Pages'],['status','Files'],['added','Date added']];

function esc(s){ return (s??'').toString().replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function toast(m){ const t=document.createElement('div'); t.className='toast'; t.textContent=m;
  document.body.appendChild(t); setTimeout(()=>t.remove(),2200); }
function key(g,b){ return g+'|'+b; }
function authorStr(b){ return (b.authors||[]).join(', '); }
function bookTags(b){ return S.groups.filter(g=>S.members.has(key(g.id,b.id))); }

async function api(method, path, body){
  const res = await fetch(path, {
    method,
    headers: { 'content-type':'application/json', ...(S.token?{authorization:'Bearer '+S.token}:{}) },
    body: body!==undefined ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401) { logout(); throw new Error('Session expired'); }
  const data = res.status===204 ? null : await res.json().catch(()=>null);
  if (!res.ok) throw new Error((data&&data.error) || ('HTTP '+res.status));
  return data;
}

// Fetch an authenticated blob and hand back an object URL. The session token
// rides the Authorization header (never the URL), so it can't leak into proxy
// logs or history; the caller is responsible for revoking the URL.
async function authBlobUrl(path){
  const res = await fetch(path, { headers: S.token?{authorization:'Bearer '+S.token}:{} });
  if (res.status === 401) { logout(); throw new Error('Session expired'); }
  if (!res.ok) throw new Error('HTTP '+res.status);
  return URL.createObjectURL(await res.blob());
}

// Load every `<img data-src>` under `root` with an auth-header fetch, swapping
// in an object URL once fetched (and revoking it after the image decodes). On
// failure we invoke the element's own onerror, so the no-cover placeholder
// still appears exactly as it did with a direct `src`.
function hydrateImages(root){
  for (const img of root.querySelectorAll('img[data-src]')){
    const path = img.getAttribute('data-src');
    img.removeAttribute('data-src');
    authBlobUrl(path).then(url=>{
      img.addEventListener('load', ()=>URL.revokeObjectURL(url), { once:true });
      img.src = url;
    }).catch(()=>{ if (typeof img.onerror === 'function') img.onerror(); });
  }
}

// Download an authenticated file by fetching it with the auth header and
// triggering a save from the resulting object URL, so the token stays out of
// the `<a href>`.
async function downloadFile(fileId, filename){
  try {
    const url = await authBlobUrl('/api/files/'+fileId);
    const a = document.createElement('a');
    a.href = url; a.download = filename || 'download';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(()=>URL.revokeObjectURL(url), 10000);
  } catch(e){ toast('Download failed'); }
}

async function login(){
  const email = document.getElementById('l-email').value.trim();
  const pass = document.getElementById('l-pass').value;
  const err = document.getElementById('l-err');
  err.textContent = '';
  try {
    const r = await api('POST','/api/auth/login',{ email, password: pass });
    S.token = r.token; S.email = r.user.email;
    localStorage.setItem('vellum_token', S.token);
    localStorage.setItem('vellum_email', S.email);
    showApp();
  } catch(e){ err.textContent = e.message; }
}

function logout(){
  S.token=null; localStorage.removeItem('vellum_token'); localStorage.removeItem('vellum_email');
  document.getElementById('app').classList.add('hidden');
  document.getElementById('login').classList.remove('hidden');
}

function showApp(){
  document.getElementById('login').classList.add('hidden');
  document.getElementById('app').classList.remove('hidden');
  document.getElementById('who').textContent = S.email || '';
  document.getElementById('tbl').classList.toggle('compact', S.compact);
  revealContentSearch();
  loadAll();
}

async function loadAll(){
  try {
    const [page, groups, members] = await Promise.all([
      api('GET','/api/books?page=1'), api('GET','/api/groups'), api('GET','/api/memberships'),
    ]);
    S.books = page.items; S.nextPage = page.next; S.total = page.total;
    S.groups = groups;
    S.members = new Set(members.map(m=>key(m.group_id,m.book_id)));
    S.selected = new Set([...S.selected].filter(id=>S.books.some(b=>b.id===id)));
    S.fTags = new Set([...S.fTags].filter(id=>groups.some(g=>g.id===id)));
    renderFilters(); render();
  } catch(e){ toast(e.message); }
}

// Appends the next page onto S.books (§3's paged /api/books) -- any other
// mutation reloads via loadAll() and resets back to the first page, so this
// only grows what's shown within the current session.
async function loadMoreBooks(){
  if (S.nextPage == null) return;
  try {
    const page = await api('GET','/api/books?page='+S.nextPage);
    S.books = S.books.concat(page.items);
    S.nextPage = page.next; S.total = page.total;
    render();
  } catch(e){ toast(e.message); }
}

// ---- filtering + sorting ------------------------------------------------

function matches(b){
  const q = S.q.trim().toLowerCase();
  if (q){
    const hay = [b.title, b.subtitle, authorStr(b), b.isbn, b.publisher]
      .filter(Boolean).join(' ').toLowerCase();
    if (!hay.includes(q)) return false;
  }
  const tags = bookTags(b);
  if (S.fUntagged){ if (tags.length) return false; }
  else if (S.fTags.size){ if (!tags.some(g=>S.fTags.has(g.id))) return false; }
  for (const m of S.fMissing){
    if (m==='file'   && b.file_count>0)          return false;
    if (m==='cover'  && b.cover_path)             return false;
    if (m==='year'   && b.published_year!=null)   return false;
    if (m==='author' && authorStr(b))             return false;
  }
  return true;
}

function sortVal(b, col){
  switch(col){
    case 'author': return authorStr(b).toLowerCase();
    case 'year':   return b.published_year ?? -Infinity;
    case 'pages':  return b.page_count ?? -Infinity;
    case 'status': return b.file_count || 0;
    case 'added':  return b.created_at || '';
    default:       return (b.title||'').toLowerCase();
  }
}

function computeRows(){
  const rows = S.books.filter(matches);
  const { col, dir } = S.sort, mul = dir==='asc' ? 1 : -1;
  rows.sort((a,b)=>{
    const x = sortVal(a,col), y = sortVal(b,col);
    if (x < y) return -mul;
    if (x > y) return mul;
    return (a.title||'').localeCompare(b.title||'');
  });
  return rows;
}

function sortBy(col){
  if (S.sort.col === col) S.sort.dir = S.sort.dir==='asc' ? 'desc' : 'asc';
  else S.sort = { col, dir: 'asc' };
  render();
}

function setQ(v){ S.q = v; S.cursor = -1; render(); }

function toggleTagFilter(id){
  S.fUntagged = false;
  S.fTags.has(id) ? S.fTags.delete(id) : S.fTags.add(id);
  S.cursor = -1; renderFilters(); render();
}
function toggleUntagged(){
  S.fUntagged = !S.fUntagged;
  if (S.fUntagged) S.fTags.clear();
  S.cursor = -1; renderFilters(); render();
}
function toggleMissing(k){
  S.fMissing.has(k) ? S.fMissing.delete(k) : S.fMissing.add(k);
  S.cursor = -1; renderFilters(); render();
}
function clearFilters(){
  S.q=''; document.getElementById('q').value='';
  S.fTags.clear(); S.fUntagged=false; S.fMissing.clear(); S.cursor=-1;
  renderFilters(); render();
}

function renderFilters(){
  document.getElementById('tagfilters').innerHTML =
    S.groups.map(g=>`<button class="fchip ${S.fTags.has(g.id)?'on':''}" onclick="toggleTagFilter('${g.id}')">${esc(g.name)}</button>`).join('')
    + `<button class="fchip ${S.fUntagged?'on':''}" onclick="toggleUntagged()">Untagged</button>`;
  document.getElementById('missingfilters').innerHTML =
    [['file','No file'],['cover','No cover'],['year','No year'],['author','No author']]
      .map(([k,l])=>`<button class="fchip ${S.fMissing.has(k)?'on':''}" onclick="toggleMissing('${k}')">${l}</button>`).join('');
}

// ---- table --------------------------------------------------------------

function arrow(col){ return S.sort.col===col ? (S.sort.dir==='asc'?' ▲':' ▼') : ''; }

function headHtml(){
  const th = (col,label,w)=>
    `<th class="sortable" ${w?`style="width:${w}"`:''} onclick="sortBy('${col}')">${label}${arrow(col)}</th>`;
  let h = '<tr><th style="width:34px"><input type="checkbox" id="selall" onchange="toggleAll(this.checked)"></th>';
  if (S.cols.has('cover'))  h += '<th style="width:44px">Cover</th>';
  h += th('title','Title');
  if (S.cols.has('author')) h += th('author','Author');
  if (S.cols.has('year'))   h += th('year','Year','70px');
  if (S.cols.has('pages'))  h += th('pages','Pages','70px');
  if (S.cols.has('status')) h += th('status','Files','90px');
  h += '<th>Tags</th>';
  if (S.cols.has('added'))  h += th('added','Added','110px');
  h += '<th style="width:120px">Actions</th></tr>';
  return h;
}

function statusCell(b){
  const f = b.file_count>0, c = !!b.cover_path;
  return `<span class="dot ${f?'on':''}" title="${f?b.file_count+' file(s)':'No file'}">●</span>${f?' '+b.file_count:''}`
       + `<span class="dot ${c?'on':''}" title="${c?'Has cover':'No cover'}" style="margin-left:8px">▣</span>`;
}

function colCount(){ return 4 + OPT_COLS.filter(([k])=>S.cols.has(k)).length; }

function render(){
  // bulk-tag dropdown
  const sel = document.getElementById('bulktag');
  sel.innerHTML = S.groups.length
    ? S.groups.map(g=>`<option value="${g.id}">${esc(g.name)}</option>`).join('')
    : '<option value="">(no tags yet)</option>';

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
        `<span class="chip">${esc(g.name)}<button title="Remove tag" onclick="removeTag('${g.id}','${b.id}')">×</button></span>`
      ).join('');
      const rowCls = [S.selected.has(b.id)?'sel':'', i===S.cursor?'cursor':''].filter(Boolean).join(' ');
      let r = `<tr class="${rowCls}"
          ondragover="dragOver(event,this)" ondragleave="dragLeave(this)" ondrop="dropOn(event,'${b.id}',this)"
          title="Drop a PDF/EPUB or cover image here">
        <td><input type="checkbox" ${S.selected.has(b.id)?'checked':''} onchange="toggleRow('${b.id}',this.checked)"></td>`;
      if (S.cols.has('cover'))
        r += `<td>${b.cover_path
          ? `<img class="thumb" data-src="/api/books/${b.id}/cover?w=160&t=${encodeURIComponent(b.updated_at||'')}" alt="" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'nothumb'}))">`
          : '<span class="nothumb"></span>'}</td>`;
      r += `<td class="title"><span class="link" onclick="titleClick('${b.id}')" ondblclick="titleDbl(event,'${b.id}')">${esc(b.title)}</span></td>`;
      if (S.cols.has('author')) r += `<td class="muted">${authorStr(b)?esc(authorStr(b)):'<span class="dim">—</span>'}</td>`;
      if (S.cols.has('year'))   r += `<td class="year editable" ondblclick="startEdit(event,'${b.id}','year')">${b.published_year??''}</td>`;
      if (S.cols.has('pages'))  r += `<td class="year">${b.page_count??''}</td>`;
      if (S.cols.has('status')) r += `<td>${statusCell(b)}</td>`;
      r += `<td>${chips}<button class="addtag" onclick="quickAdd(this,'${b.id}')">＋ tag</button></td>`;
      if (S.cols.has('added'))  r += `<td class="muted">${esc((b.created_at||'').slice(0,10))}</td>`;
      r += `<td class="actions">
        <button class="btn sm" onclick="pickUpload('${b.id}')">Upload</button>
        <button class="btn sm" onclick="openLink('${b.id}')">Link</button>
      </td></tr>`;
      return r;
    }).join('');
    hydrateImages(rows);
  }

  const selShown = S.view.filter(b=>S.selected.has(b.id)).length;
  document.getElementById('count').textContent =
    `${S.view.length} shown · ${S.total} total · ${S.selected.size} selected`;
  document.getElementById('selall').checked = S.view.length>0 && selShown===S.view.length;

  // Filtering/search/sort/tagging all run client-side over S.books, so while
  // more pages remain (S.nextPage != null) a filter can show "no matches"
  // even though a later page would have some -- "Load more" is how the user
  // resolves that, same tradeoff every client-side-filtered paged list has.
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

function toggleRow(id, on){ on?S.selected.add(id):S.selected.delete(id); render(); }
function toggleAll(on){ for(const b of S.view){ on?S.selected.add(b.id):S.selected.delete(b.id); } render(); }

// ---- inline editing -----------------------------------------------------

// Single click on a title opens the detail modal; a double click edits it in
// place. We defer the open briefly so a double click can cancel it.
let clickTimer = null;
function titleClick(id){
  if (clickTimer) return;                       // second click of a dblclick
  clickTimer = setTimeout(()=>{ clickTimer=null; openDetail(id); }, 220);
}
function titleDbl(ev, id){
  if (clickTimer){ clearTimeout(clickTimer); clickTimer=null; }
  startEdit(ev, id, 'title');
}

function startEdit(ev, id, field){
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

async function commitEdit(id, field, raw){
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

// ---- add / search / create (unchanged behaviour) ------------------------

// The Add-book dialog is a small editable metadata form. Attaching a file (or
// clicking "Look up online") calls /api/metadata/analyze, which parses the file
// name and runs one online search, and pre-fills the fields. Create posts the
// (possibly edited) result to from-search so authors, genres and a cover are
// stored too; a hidden AB.proposal keeps the parts with no visible field
// (cover, subjects, work key).
function openAddBook(){
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

function pickAbFile(){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub';
  input.onchange = ()=>{ if (input.files[0]) setAbFile(input.files[0]); };
  input.click();
}
async function setAbFile(file){
  const kind = await classify(file);
  if (kind !== 'pdf' && kind !== 'epub'){ toast('Only PDF or EPUB can be attached'); return; }
  AB.file = file;
  const d = document.getElementById('ab-drop');
  if (d) d.textContent = 'Attached: ' + file.name;
  await analyzeFile(file.name);
}
function abDragOver(e){ e.preventDefault(); document.getElementById('ab-drop').classList.add('over'); }
function abDragLeave(){ const d = document.getElementById('ab-drop'); if (d) d.classList.remove('over'); }
function abDrop(e){ e.preventDefault(); abDragLeave(); const f = e.dataTransfer.files[0]; if (f) setAbFile(f); }

function fillForm(r){
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
async function analyzeFile(filename){
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
async function runLookup(){
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

function pickCandidate(i){
  fillForm(AB.results[i]);
  document.getElementById('ab-status').textContent = 'Filled from the selected match — review, then Create.';
}

async function createBook(){
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

// ---- CSV import ---------------------------------------------------------

// Import's duplicate-title check (parseImport below) only sees S.books, so
// with pages still unloaded (§3) it would miss dupes past the first page and
// create real duplicates -- load everything before the dialog opens rather
// than caveat around a wrong dedupe result.
async function openImport(){
  while (S.nextPage != null) await loadMoreBooks();
  IMP.items = [];
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(640px,95vw)">
      <h2>Import books from CSV</h2>
      <p class="muted">First row is the header. A <b>title</b> column is required;
        <b>subtitle, year, publisher, isbn, pages</b> are optional. (Authors can’t be
        set through the API and are ignored.)</p>
      <textarea id="imp-text" rows="7" placeholder="title,year,publisher
The Odyssey,1996,Penguin" oninput="importPreview()"></textarea>
      <div class="row" style="justify-content:flex-start; margin-top:8px">
        <button class="btn" onclick="importPickFile()">Choose CSV file…</button>
      </div>
      <div class="checkline">
        <input type="checkbox" id="imp-dupes" onchange="importPreview()">
        <label for="imp-dupes">Allow duplicate titles</label>
      </div>
      <div id="imp-status" class="muted" style="margin:8px 0; min-height:1.2em"></div>
      <div class="row">
        <button class="btn" onclick="closeModal()">Close</button>
        <button class="btn primary" id="imp-do" disabled onclick="importDo()">Import</button>
      </div>
    </div>
   </div>`;
}

function importPickFile(){
  const i = document.createElement('input');
  i.type='file'; i.accept='.csv,text/csv,text/plain';
  i.onchange = async ()=>{ const f=i.files[0]; if(!f) return;
    document.getElementById('imp-text').value = await f.text(); importPreview(); };
  i.click();
}

// A small CSV parser: handles quoted cells, escaped "" quotes, and \r\n.
function parseCSV(text){
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

function parseImport(text){
  const rows = parseCSV(text);
  if (!rows.length) return { error:'Nothing to parse.' };
  const header = rows[0].map(h=>h.trim().toLowerCase());
  const idx = names=>{ for(const n of names){ const i=header.indexOf(n); if(i>=0) return i; } return -1; };
  const iTitle=idx(['title','name']);
  if (iTitle<0) return { error:'CSV needs a "title" column in the first row.' };
  const iSub=idx(['subtitle']), iAuth=idx(['author','authors']),
        iYear=idx(['year','published_year','published']), iPub=idx(['publisher']),
        iIsbn=idx(['isbn','isbn13','isbn_13']), iPages=idx(['pages','page_count']);
  const allow = document.getElementById('imp-dupes').checked;
  const existing = new Set(S.books.map(b=>(b.title||'').trim().toLowerCase()));
  const items=[]; let dupes=0;
  for (let r=1;r<rows.length;r++){
    const row=rows[r], title=(row[iTitle]||'').trim();
    if (!title) continue;
    if (!allow && existing.has(title.toLowerCase())){ dupes++; continue; }
    const it={ title };
    if (iSub>=0 && row[iSub]) it.subtitle=row[iSub].trim();
    if (iPub>=0 && row[iPub]) it.publisher=row[iPub].trim();
    if (iIsbn>=0 && row[iIsbn]) it.isbn=row[iIsbn].trim();
    if (iYear>=0 && row[iYear]){ const y=parseInt(row[iYear],10); if(!isNaN(y)) it.published_year=y; }
    if (iPages>=0 && row[iPages]){ const p=parseInt(row[iPages],10); if(!isNaN(p)) it.page_count=p; }
    items.push(it); existing.add(title.toLowerCase());
  }
  return { items, dupes, authorsIgnored: iAuth>=0 };
}

function importPreview(){
  const st = document.getElementById('imp-status');
  const p = parseImport(document.getElementById('imp-text').value);
  if (p.error){ IMP.items=[]; st.textContent=p.error; document.getElementById('imp-do').disabled=true; return; }
  IMP.items = p.items;
  st.textContent = `${p.items.length} new book(s) ready`
    + (p.dupes?`, ${p.dupes} duplicate title(s) skipped`:'')
    + (p.authorsIgnored?` · author column ignored`:'') + '.';
  document.getElementById('imp-do').disabled = p.items.length===0;
}

async function importDo(){
  if (!IMP.items.length) return;
  const btn = document.getElementById('imp-do');
  btn.disabled=true; btn.innerHTML='<span class="spin"></span>Importing…';
  let ok=0;
  for (const it of IMP.items){ try { await api('POST','/api/books', it); ok++; } catch(_){} }
  closeModal(); await loadAll(); toast('Imported '+ok+' book(s)');
}

// ---- export -------------------------------------------------------------

function download(name, text, mime){
  const url = URL.createObjectURL(new Blob([text],{type:mime}));
  const a = document.createElement('a'); a.href=url; a.download=name; a.click();
  setTimeout(()=>URL.revokeObjectURL(url), 1000);
}
function csvCell(v){
  if (v==null) v='';
  v = String(v);
  return /[",\n]/.test(v) ? '"'+v.replace(/"/g,'""')+'"' : v;
}
// Exports only cover what's loaded into S.books (§3's paged /api/books), so
// a library with more pages remaining needs "Load more" clicked first or the
// export silently leaves books out -- warn rather than let that pass quietly.
function exportCaveat(){
  return S.nextPage == null ? '' : ` (${S.total-S.books.length} more not loaded — click "Load more" first for a full export)`;
}
function exportJSON(){
  download('vellum-books.json', JSON.stringify(S.view, null, 2), 'application/json');
  toast('Exported '+S.view.length+' book(s)'+exportCaveat());
}
function exportCSV(){
  const cols = ['title','subtitle','authors','published_year','publisher','isbn','page_count','file_count','has_cover','tags','created_at'];
  const lines = [cols.join(',')];
  for (const b of S.view){
    const rec = { ...b, authors:authorStr(b), has_cover: b.cover_path?'yes':'no',
                  tags: bookTags(b).map(g=>g.name).join('; ') };
    lines.push(cols.map(c=>csvCell(rec[c])).join(','));
  }
  download('vellum-books.csv', lines.join('\n'), 'text/csv');
  toast('Exported '+S.view.length+' book(s)'+exportCaveat());
}

// ---- columns + density --------------------------------------------------

function openColumns(){
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal">
      <h2>Columns</h2>
      <div class="colgrid">
        ${OPT_COLS.map(([k,l])=>`<label><input type="checkbox" ${S.cols.has(k)?'checked':''} onchange="toggleCol('${k}',this.checked)">${l}</label>`).join('')}
      </div>
      <div class="row"><button class="btn primary" onclick="closeModal()">Done</button></div>
    </div>
   </div>`;
}
function toggleCol(k, on){
  on ? S.cols.add(k) : S.cols.delete(k);
  localStorage.setItem('vellum_cols', JSON.stringify([...S.cols]));
  render();
}
function toggleDensity(){
  S.compact = !S.compact;
  localStorage.setItem('vellum_density', S.compact?'1':'0');
  document.getElementById('tbl').classList.toggle('compact', S.compact);
}

// ---- uploads (unchanged) ------------------------------------------------

async function classify(file){
  const buf = new Uint8Array(await file.slice(0,16).arrayBuffer());
  const m = sig => sig.every((byte,i)=>buf[i]===byte);
  if (m([0x25,0x50,0x44,0x46])) return 'pdf';
  if (m([0xFF,0xD8,0xFF]) || m([0x89,0x50,0x4E,0x47]) || m([0x47,0x49,0x46,0x38])) return 'image';
  if (m([0x50,0x4B,0x03,0x04]) && file.name.toLowerCase().endsWith('.epub')) return 'epub';
  return 'unsupported';
}

function showProgress(label){
  let el = document.getElementById('uprog');
  if (!el){
    el = document.createElement('div');
    el.id = 'uprog'; el.className = 'uprog';
    el.innerHTML = '<div class="uprog-label"></div><div class="uprog-track"><div class="uprog-bar"></div></div><div class="uprog-pct"></div>';
    document.body.appendChild(el);
  }
  el.querySelector('.uprog-label').textContent = label;
  el.querySelector('.uprog-bar').style.width = '0%';
  el.querySelector('.uprog-pct').textContent = '0%';
  el.style.display = 'flex';
}
function setProgress(fraction){
  const el = document.getElementById('uprog'); if (!el) return;
  const pct = Math.round(fraction * 100);
  el.querySelector('.uprog-bar').style.width = pct + '%';
  el.querySelector('.uprog-pct').textContent = (pct >= 100 ? 'finishing…' : pct + '%');
}
function hideProgress(){ const el = document.getElementById('uprog'); if (el) el.style.display = 'none'; }

function xhrUpload(method, url, file, mime){
  return new Promise((resolve, reject)=>{
    const xhr = new XMLHttpRequest();
    xhr.open(method, url);
    xhr.setRequestHeader('authorization', 'Bearer ' + S.token);
    xhr.setRequestHeader('content-type', mime);
    xhr.upload.onprogress = e => { if (e.lengthComputable) setProgress(e.loaded / e.total); };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) return resolve();
      let msg = 'Upload failed (HTTP ' + xhr.status + ')';
      try { const j = JSON.parse(xhr.responseText); if (j.error) msg = j.error; } catch(_) {}
      reject(new Error(msg));
    };
    xhr.onerror = () => reject(new Error('Network error during upload'));
    xhr.send(file);
  });
}

async function uploadTo(id, file){
  const kind = await classify(file);
  if (kind !== 'image' && kind !== 'pdf' && kind !== 'epub'){
    toast('Only PDF, EPUB, or image files are accepted');
    return false;
  }
  showProgress('Uploading ' + file.name);
  try {
    if (kind === 'image'){
      await xhrUpload('PUT', '/api/books/'+id+'/cover', file, file.type || 'image/jpeg');
      toast('Cover updated'); await loadAll();
    } else {
      const mime = kind === 'epub' ? 'application/epub+zip' : 'application/pdf';
      await xhrUpload('POST', '/api/books/'+id+'/files?filename='+encodeURIComponent(file.name), file, mime);
      toast('Uploaded ' + file.name);
      await enrichBook(id);          // fill missing author/year/etc. from the title
      await loadAll();
    }
    return true;
  } catch(e){ toast(e.message); return false; }
  finally { hideProgress(); }
}

// Ask the server to fill a book's empty fields from an online metadata lookup.
// Best-effort: a miss or a network error leaves the book untouched.
async function enrichBook(id){
  try { await api('POST','/api/books/'+id+'/enrich'); }
  catch(_){ /* non-fatal — the upload/create still succeeded */ }
}

async function enrichSelected(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  const ids = [...S.selected];
  showProgress('Fetching metadata…');
  let done = 0;
  for (const id of ids){ await enrichBook(id); setProgress(++done/ids.length); }
  hideProgress(); await loadAll(); toast('Fetched metadata for '+ids.length+' book(s)');
}

function pickUpload(id){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub,image/*';
  input.onchange = ()=>{ if (input.files[0]) uploadTo(id, input.files[0]); };
  input.click();
}

// Apply one picked file to every selected book (a shared cover, say).
function uploadToSelected(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub,image/*';
  input.onchange = async ()=>{
    const f = input.files[0]; if (!f) return;
    const kind = await classify(f);
    if (kind!=='image' && kind!=='pdf' && kind!=='epub'){ toast('Only PDF, EPUB, or image files'); return; }
    const ids = [...S.selected];
    const what = kind==='image' ? 'cover' : 'file';
    if (!confirm(`Apply this ${what} (${f.name}) to ${ids.length} selected book(s)?`)) return;
    let ok=0;
    for (const id of ids){
      showProgress('Uploading to '+ok+'/'+ids.length);
      try {
        if (kind==='image') await xhrUpload('PUT','/api/books/'+id+'/cover', f, f.type||'image/jpeg');
        else { const mime=kind==='epub'?'application/epub+zip':'application/pdf';
               await xhrUpload('POST','/api/books/'+id+'/files?filename='+encodeURIComponent(f.name), f, mime); }
        ok++;
      } catch(e){ toast(e.message); }
    }
    hideProgress(); await loadAll(); toast('Applied to '+ok+' book(s)');
  };
  input.click();
}

function dragOver(e, tr){ e.preventDefault(); tr.classList.add('drop'); }
function dragLeave(tr){ tr.classList.remove('drop'); }
function dropOn(e, id, tr){
  e.preventDefault(); tr.classList.remove('drop');
  const f = e.dataTransfer.files[0];
  if (f) uploadTo(id, f);
}

// ---- tags ---------------------------------------------------------------

async function createTag(){
  const input = document.getElementById('newtag');
  const name = input.value.trim();
  if (!name) return;
  try { await api('POST','/api/groups',{ name }); input.value=''; await loadAll(); toast('Tag created'); }
  catch(e){ toast(e.message); }
}

async function addMember(groupId, bookId){
  if (S.members.has(key(groupId,bookId))) return;
  await api('POST', `/api/groups/${groupId}/books`, { book_id: bookId });
}
async function removeTag(groupId, bookId){
  try { await api('DELETE', `/api/groups/${groupId}/books/${bookId}`); await loadAll(); }
  catch(e){ toast(e.message); }
}

async function bulkTag(add){
  const groupId = document.getElementById('bulktag').value;
  if (!groupId || S.selected.size===0) { toast('Pick a tag and select some books'); return; }
  try {
    for (const bookId of S.selected){
      if (add) await addMember(groupId, bookId);
      else if (S.members.has(key(groupId,bookId)))
        await api('DELETE', `/api/groups/${groupId}/books/${bookId}`);
    }
    await loadAll(); toast(add?'Tagged':'Untagged');
  } catch(e){ toast(e.message); }
}

function quickAdd(btn, bookId){
  const avail = S.groups.filter(g=>!S.members.has(key(g.id,bookId)));
  if (avail.length===0){ toast('No more tags — create one first'); return; }
  const sel = document.createElement('select');
  sel.innerHTML = '<option value="">Add tag…</option>' +
    avail.map(g=>`<option value="${g.id}">${esc(g.name)}</option>`).join('');
  sel.onchange = async ()=>{
    if (!sel.value) return;
    try { await addMember(sel.value, bookId); await loadAll(); }
    catch(e){ toast(e.message); }
  };
  btn.replaceWith(sel); sel.focus();
}

// ---- bulk edit + delete -------------------------------------------------

function openBulkEdit(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal">
      <h2>Edit ${S.selected.size} selected</h2>
      <label>Publisher</label><input id="be-pub" type="text">
      <label>Year</label><input id="be-year" type="text">
      <p class="muted" style="margin-top:10px">Blank fields are left unchanged.</p>
      <div class="row">
        <button class="btn" onclick="closeModal()">Close</button>
        <button class="btn primary" onclick="bulkEditApply()">Apply</button>
      </div>
    </div>
   </div>`;
}
async function bulkEditApply(){
  const pub = document.getElementById('be-pub').value.trim();
  const yr  = document.getElementById('be-year').value.trim();
  const body = {};
  if (pub) body.publisher = pub;
  if (yr){ const y=parseInt(yr,10); if(isNaN(y)){ toast('Year must be a number'); return; } body.published_year=y; }
  if (!Object.keys(body).length){ toast('Nothing to change'); return; }
  const ids=[...S.selected];
  try { for(const id of ids) await api('PATCH','/api/books/'+id, body);
        closeModal(); await loadAll(); toast('Updated '+ids.length+' book(s)'); }
  catch(e){ toast(e.message); }
}

async function deleteSelected(){
  if (S.selected.size===0) return;
  if (!confirm(`Delete ${S.selected.size} book(s)? This cannot be undone.`)) return;
  try { for (const id of S.selected) await api('DELETE', `/api/books/${id}`);
        S.selected.clear(); await loadAll(); toast('Deleted'); }
  catch(e){ toast(e.message); }
}

// ---- detail (unchanged) -------------------------------------------------

function fmtSize(b){ return b>=1048576 ? (b/1048576).toFixed(1)+' MB' : Math.max(1,Math.round(b/1024))+' KB'; }

async function openDetail(id){
  let d;
  try { d = await api('GET','/api/books/'+id+'/detail'); }
  catch(e){ toast(e.message); return; }
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
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(720px,95vw); max-height:90vh; overflow:auto">
      <div style="display:flex; gap:16px">
        <div class="cover-box" onclick="detailPick('${id}','image/*')">
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
      <label>Files</label>
      ${files}
      <div class="row" style="justify-content:space-between; margin-top:16px">
        <div>
          <button class="btn danger" onclick="deleteBook('${id}')">Delete</button>
          <button class="btn" onclick="enrichFromDetail('${id}')">Fetch metadata</button>
        </div>
        <div>
          <button class="btn" onclick="closeModal()">Close</button>
          <button class="btn primary" onclick="saveDetail('${id}')">Save</button>
        </div>
      </div>
    </div>
   </div>`;
  const modalRoot = document.getElementById('modal-root');
  hydrateImages(modalRoot);
  modalRoot.querySelectorAll('button[data-fid]').forEach(btn =>
    btn.onclick = () => downloadFile(btn.dataset.fid, btn.dataset.fname));
}

function detailPick(id, accept){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = accept;
  input.onchange = async ()=>{
    if (!input.files[0]) return;
    await uploadTo(id, input.files[0]);
    openDetail(id);
  };
  input.click();
}

async function saveDetail(id){
  const body = {
    title: document.getElementById('d-title').value.trim(),
    subtitle: document.getElementById('d-subtitle').value,
    description: document.getElementById('d-desc').value,
  };
  const y = document.getElementById('d-year').value.trim();
  if (y && !isNaN(parseInt(y,10))) body.published_year = parseInt(y,10);
  if (!body.title){ toast('Title cannot be empty'); return; }
  try { await api('PATCH','/api/books/'+id, body); closeModal(); await loadAll(); toast('Saved'); }
  catch(e){ toast(e.message); }
}

async function enrichFromDetail(id){
  showProgress('Fetching metadata…');
  await enrichBook(id);
  hideProgress(); await loadAll(); toast('Fetched metadata'); openDetail(id);
}

async function deleteBook(id){
  if (!confirm('Delete this book? This cannot be undone.')) return;
  try { await api('DELETE','/api/books/'+id); closeModal(); await loadAll(); toast('Deleted'); }
  catch(e){ toast(e.message); }
}

// ---- public links (unchanged) -------------------------------------------

function openLink(bookId){
  const book = S.books.find(b=>b.id===bookId);
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal">
      <h2>Public link</h2>
      <p class="muted">${esc(book?book.title:'')}</p>
      <div class="checkline"><input type="checkbox" id="m-onetime"><label for="m-onetime">One-time download</label></div>
      <label>Expires on (optional)</label>
      <input type="date" id="m-exp">
      <div id="m-out"></div>
      <div class="row">
        <button class="btn" onclick="closeModal()">Close</button>
        <button class="btn primary" id="m-create" onclick="createLink('${bookId}')">Create link</button>
      </div>
    </div>
   </div>`;
}
function closeModal(){ document.getElementById('modal-root').innerHTML=''; }

// ---- server certificate (for importing into the app) --------------------

let _certPem = '';

// Show the server's TLS certificate so it can be imported into the Vellum app
// (Server -> Import) instead of copying cert.pem off the box by hand. 404 when
// the server runs over plain HTTP — there's nothing to import.
async function showCert(){
  let cert;
  try { cert = await api('GET','/api/cert'); }
  catch(e){
    toast(/not using TLS/.test(e.message)
      ? 'This server runs over HTTP — there is no certificate to import.'
      : e.message);
    return;
  }
  _certPem = cert.pem;
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Server certificate</h2>
      <p class="muted" style="margin:0 0 12px">Import this into the Vellum app
        (Server → Import) to connect over HTTPS. Check the fingerprint matches the
        one the server logged on startup before trusting it.</p>
      <label>SHA-256 fingerprint</label>
      <div style="font-family:monospace; font-size:12px; word-break:break-all;
                  padding:8px 10px; border:1px solid var(--line); border-radius:8px;
                  background:var(--row); margin-bottom:10px">${esc(cert.fingerprint)}</div>
      <label>Certificate (PEM)</label>
      <textarea readonly rows="8" onclick="this.select()"
                style="width:100%; font-family:monospace; font-size:12px">${esc(cert.pem)}</textarea>
      <div class="row" style="justify-content:flex-end; gap:8px; margin-top:12px">
        <button class="btn" onclick="copyCert()">Copy PEM</button>
        <button class="btn" onclick="downloadCert()">Download cert.pem</button>
        <button class="btn primary" onclick="closeModal()">Close</button>
      </div>
    </div>
   </div>`;
}

function copyCert(){
  if (navigator.clipboard) {
    navigator.clipboard.writeText(_certPem)
      .then(()=>toast('Certificate copied'), ()=>toast('Copy failed — select the text and copy manually'));
  } else {
    toast('Select the text and copy manually');
  }
}

function downloadCert(){
  const blob = new Blob([_certPem], { type:'application/x-pem-file' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = 'cert.pem';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(()=>URL.revokeObjectURL(url), 10000);
}

async function createLink(bookId){
  const oneTime = document.getElementById('m-onetime').checked;
  const exp = document.getElementById('m-exp').value;
  try {
    const r = await api('POST','/api/share-links', {
      book_id: bookId, one_time: oneTime, ...(exp?{expires_at:exp}:{}),
    });
    const out = document.getElementById('m-out');
    out.innerHTML = `<label>Share this link</label>
      <div class="linkout" id="m-url">${esc(r.url)}</div>
      <div class="row"><button class="btn" onclick="copyUrl('${esc(r.url)}')">Copy</button></div>`;
    document.getElementById('m-create').disabled = true;
  } catch(e){ toast(e.message); }
}
function copyUrl(url){ navigator.clipboard.writeText(url).then(()=>toast('Copied')); }

// ---- keyboard navigation ------------------------------------------------

document.addEventListener('keydown', e=>{
  if (!document.getElementById('login').classList.contains('hidden')) return;   // logged out
  const modalOpen = document.getElementById('modal-root').innerHTML !== '';
  if (e.key === 'Escape'){ if (modalOpen) closeModal(); return; }
  if (modalOpen) return;
  const t = e.target, tag = (t.tagName||'').toLowerCase();
  if (tag==='input' || tag==='textarea' || tag==='select' || t.isContentEditable) return;

  if (e.key === '/'){ e.preventDefault(); document.getElementById('q').focus(); return; }
  if (!S.view.length) return;
  if (e.key === 'ArrowDown'){ e.preventDefault(); S.cursor = Math.min(S.view.length-1, S.cursor+1); afterCursorMove(); }
  else if (e.key === 'ArrowUp'){ e.preventDefault(); S.cursor = Math.max(0, S.cursor<0?0:S.cursor-1); afterCursorMove(); }
  else if (e.key === ' ' && S.cursor>=0){ e.preventDefault(); const id=S.view[S.cursor].id; toggleRow(id, !S.selected.has(id)); }
  else if (e.key === 'Enter' && S.cursor>=0){ openDetail(S.view[S.cursor].id); }
});
function afterCursorMove(){
  render();
  const el = document.querySelector('tr.cursor');
  if (el) el.scrollIntoView({ block:'nearest' });
}

window.addEventListener('resize', ()=>{
  const tb = document.getElementById('topbar');
  if (tb) document.documentElement.style.setProperty('--thead-top', tb.offsetHeight+'px');
});

// boot
if (S.token) showApp();


// ---- Server dashboard (plan 5 #37) ----------------------------------------
// Deliberately small: for a personal server, "how big is my library and how much
// disk is it using" is the question an operator actually has, and a metrics
// stack would be more machinery than the thing it observes.
function fmtBytes(n){
  if (!n) return '0 B';
  const units = ['B','KB','MB','GB','TB'];
  let i = 0, v = n;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(1)) + ' ' + units[i];
}

// ---- content search (plan 5 #32) ----------------------------------------
//
// Searching the *text* of the books, which only a server can do. The button is
// revealed by the capability handshake rather than by trying and failing.

async function revealContentSearch(){
  try {
    const caps = await api('GET','/api/capabilities');
    if (!(caps.features||[]).includes('content_search')) return;
  } catch(e){ return; }
  document.getElementById('contentbtn').classList.remove('hidden');
  document.getElementById('contentsep').classList.remove('hidden');
}

async function searchContents(){
  // Reuses whatever is already typed in the filter box: you searched, found
  // nothing, and now want to look deeper — that is the moment this is for.
  const q = (document.getElementById('q').value || '').trim();
  if (!q){ toast('Type something to search for first.'); return; }
  let body;
  try {
    body = await api('GET','/api/search?q='+encodeURIComponent(q));
  } catch(e){ toast(e.message); return; }

  const hits = body.hits || [];
  // The snippet arrives with [brackets] around the match; they become <mark>
  // *after* escaping, so a book that literally contains "<script>" cannot
  // inject anything.
  const rows = hits.length ? hits.map(h => `
    <div class="row" style="flex-direction:column; align-items:flex-start; gap:2px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <div><strong>${esc(h.title)}</strong>
        <span class="muted">· p. ${esc(String(h.page))}</span></div>
      <div class="muted" style="font-size:13px">${
        esc(h.snippet).replace(/\[/g,'<mark>').replace(/\]/g,'</mark>')
      }</div>
    </div>`).join('')
    : '<p class="muted">No book contains that.</p>';

  let progress = '';
  try {
    const status = await api('GET','/api/search/status');
    const counts = status.counts || {};
    const pending = counts.pending || 0;
    if (pending) progress = `<p class="muted">Still indexing ${pending} file(s) —
      results will improve.</p>`;
  } catch(e){ /* progress is a nicety, not a requirement */ }

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(680px,95vw)">
      <h2 style="margin:0 0 4px">Inside your books</h2>
      <p class="muted" style="margin:0 0 12px">Matches for
        \u201c${esc(q)}\u201d in the text of the books on this server.</p>
      ${progress}
      <div style="max-height:60vh; overflow:auto">${rows}</div>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

async function showStats(){
  let stats;
  try {
    stats = await api('GET','/api/admin/stats');
  } catch(e){
    // Only the master may read this; say so rather than showing a raw 403.
    toast(/master/.test(e.message)
      ? 'Only the library owner can see server statistics.'
      : e.message);
    return;
  }
  const rows = [
    ['Books', stats.books],
    ['Authors', stats.authors],
    ['Accounts', stats.users],
    ['Attached files', stats.files],
    ['Shares', stats.shares],
    ['Public links', stats.share_links],
    ['Book files and covers on disk', fmtBytes(stats.blob_bytes)],
    ['Database (including WAL)', fmtBytes(stats.database_bytes)],
    ['Server version', stats.server_version],
  ].map(([k,v]) => `<div class="row" style="justify-content:space-between; gap:16px;
      padding:6px 0; border-bottom:1px solid var(--line)">
      <span>${esc(k)}</span><strong>${esc(String(v))}</strong></div>`).join('');
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(480px,95vw)">
      <h2 style="margin:0 0 4px">Server</h2>
      <p class="muted" style="margin:0 0 12px">What this library costs on disk,
        and what is in it.</p>
      ${rows}
      <p class="muted" style="margin:12px 0 0">Every response carries an
        <code>X-Request-Id</code>; quote it when reporting a problem and it can be
        found in the server log.</p>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn primary" onclick="closeModal()">Close</button>
      </div>
    </div>
   </div>`;
}
