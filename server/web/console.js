// The bearer token lives in sessionStorage, not localStorage (plan 5 #35,
// §0.12): a token stolen through an XSS then dies with the tab instead of
// persisting across every future visit. The CSP already blocks the obvious
// exfiltration paths, so this is defence in depth rather than a fix for a known
// hole — the cost is signing in again in a new tab, which is the right trade for
// a management console.
const S = { token: sessionStorage.getItem('vellum_token'), email: sessionStorage.getItem('vellum_email'),
            books: [], groups: [], members: new Set(), selected: new Set(),
            view: [], cursor: -1,
            // /api/books?page=1 (§3) loads the library a page at a time instead
            // of unbounded; nextPage is the next page to fetch via "Load more",
            // null once every book is loaded. total is the server's count of
            // every visible book, independent of how many pages are in S.books.
            nextPage: 1, total: 0,
            // Search, sort and filters are now *server-side* (plan 5 #35): a
            // 10,000-book library shouldn't have to reach the browser before it
            // can be narrowed. One tag and one "missing" at a time, which is
            // what the server takes and what people actually use.
            q: '', sort: { col: 'title', dir: 'asc' },
            fTag: null, fMissing: null,
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

// ---- delegated events ---------------------------------------------------
//
// **Why nothing here uses `onclick="fn('${value}')"`.** That is a JS string
// inside an HTML attribute, and an HTML parser decodes character references in
// attribute values *before* the JS engine is handed the source. So `esc()` —
// which turns `'` into `&#39;` — is undone on the way in, and a room named
//
//     My room'+alert(document.domain)+'
//
// executes when the master opens the rooms list. Any member can publish a room,
// so that was stored XSS from a low-privileged account into the admin console
// (security audit, S5).
//
// Escaping for a nested context correctly is possible and is a trap: it has to
// be right every time, at thirty call sites, forever. Data attributes are plain
// text — escaped once as HTML, read back through `dataset`, never parsed as
// code — so the nesting simply does not exist.
const ACTIONS = {
  tagfilter: el => toggleTagFilter(el.dataset.id),
  missing: el => toggleMissing(el.dataset.key),
  sort: el => sortBy(el.dataset.col),
  removetag: el => removeTag(el.dataset.group, el.dataset.book),
  titleclick: el => titleClick(el.dataset.book),
  quickadd: el => quickAdd(el, el.dataset.book),
  openreader: el => openReader(el.dataset.book),
  pickupload: el => pickUpload(el.dataset.book),
  openlink: el => openLink(el.dataset.book),
  detailpick: el => detailPick(el.dataset.book, el.dataset.accept),
  deletebook: el => deleteBook(el.dataset.book),
  enrichdetail: el => enrichFromDetail(el.dataset.book),
  savedetail: el => saveDetail(el.dataset.book),
  canceldetail: () => cancelDetail(),
  pickdetail: el => pickDetailCandidate(Number(el.dataset.i)),
  createlink: el => createLink(el.dataset.book),
  copyurl: el => copyUrl(el.dataset.url),
  decide: el => decideRequest(el.dataset.id, el.dataset.decision),
  viewroom: el => window.open('/room/' + encodeURIComponent(el.dataset.id), '_blank', 'noopener'),
  shareroom: el => shareRoom(el.dataset.id, el.dataset.name),
  activity: el => showActivity(el.dataset.before === '' ? null : Number(el.dataset.before)),
  setrole: el => setRole(el.dataset.id, el.dataset.master === '1'),
  resetfor: el => resetFor(el.dataset.email),
  removeperson: el => removePerson(el.dataset.id, el.dataset.email),
  revokeinvite: el => revokeInvite(el.dataset.id),
  revokelink: el => revokeLink(el.dataset.id),
  revokeshare: el => revokeShare(el.dataset.id),
  applyview: el => applyView(el.dataset.name),
  deleteview: el => deleteView(el.dataset.name),
};

const DBL_ACTIONS = {
  titleedit: (el, ev) => titleDbl(ev, el.dataset.book),
  startedit: (el, ev) => startEdit(ev, el.dataset.book, el.dataset.field),
};

const CHANGE_ACTIONS = {
  togglerow: el => toggleRow(el.dataset.book, el.checked),
  importtoggle: el => importToggle(Number(el.dataset.index), el.checked),
  togglecol: el => toggleCol(el.dataset.key, el.checked),
};

function delegate(type, table, attr) {
  document.addEventListener(type, ev => {
    const el = ev.target.closest('[' + attr + ']');
    if (!el) return;
    const fn = table[el.getAttribute(attr)];
    if (fn) fn(el, ev);
  });
}
delegate('click', ACTIONS, 'data-act');
delegate('dblclick', DBL_ACTIONS, 'data-dblact');
delegate('change', CHANGE_ACTIONS, 'data-changeact');
document.addEventListener('drop', ev => {
  const el = ev.target.closest('[data-dropbook]');
  if (el) dropOn(ev, el.dataset.dropbook, el);
});

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
    sessionStorage.setItem('vellum_token', S.token);
    sessionStorage.setItem('vellum_email', S.email);
    showApp();
  } catch(e){ err.textContent = e.message; }
}

// ---- first run: creating the master account ------------------------------
//
// A brand-new server has nobody to log in as, and the console used to show a
// login box regardless — a dead end unless you knew the app or curl could
// register for you. `GET /api/auth/registration` says whether that first
// account can still be made; the form appears only in that window, because
// once a master exists the endpoint permanently answers "closed".

async function checkRegistration(){
  try {
    const r = await api('GET','/api/auth/registration');
    if (!r || !r.open) return;
    document.getElementById('r-token').classList.toggle('hidden', !r.bootstrap_token_required);
    showRegister();
  } catch(e){
    // An older server has no such route. Leaving the login form up is exactly
    // the old behaviour, so a 404 here is not worth saying anything about.
  }
}

function showRegister(){
  document.getElementById('login').classList.add('hidden');
  document.getElementById('register').classList.remove('hidden');
  document.getElementById('r-email').focus();
}

function showLogin(){
  document.getElementById('register').classList.add('hidden');
  document.getElementById('login').classList.remove('hidden');
  document.getElementById('l-to-register').classList.remove('hidden');
}

async function register(){
  const email = document.getElementById('r-email').value.trim();
  const name = document.getElementById('r-name').value.trim();
  const pass = document.getElementById('r-pass').value;
  const tokenField = document.getElementById('r-token');
  const err = document.getElementById('r-err');
  err.textContent = '';
  try {
    const body = { email, display_name: name, password: pass };
    if (!tokenField.classList.contains('hidden')) {
      body.bootstrap_token = tokenField.value.trim();
    }
    const r = await api('POST','/api/auth/register', body);
    // Registering signs you in — the server hands back a session token, so
    // making the account and then being shown a login form would be silly.
    S.token = r.token; S.email = r.user.email;
    sessionStorage.setItem('vellum_token', S.token);
    sessionStorage.setItem('vellum_email', S.email);
    document.getElementById('register').classList.add('hidden');
    showApp();
  } catch(e){ err.textContent = e.message; }
}

function logout(){
  S.token=null; sessionStorage.removeItem('vellum_token'); sessionStorage.removeItem('vellum_email');
  document.getElementById('app').classList.add('hidden');
  document.getElementById('login').classList.remove('hidden');
}

function showApp(){
  document.getElementById('login').classList.add('hidden');
  document.getElementById('app').classList.remove('hidden');
  document.getElementById('who').textContent = S.email || '';
  document.getElementById('tbl').classList.toggle('compact', S.compact);
  revealContentSearch();
  renderViews();
  loadAll();
}

// The query string every book fetch shares, so page 1 and "Load more" can
// never disagree about what is being listed.
function booksQuery(page){
  const p = new URLSearchParams({ page: String(page), sort: S.sort.col, dir: S.sort.dir });
  if (S.q.trim()) p.set('q', S.q.trim());
  if (S.fTag) p.set('tag', S.fTag);
  if (S.fMissing) p.set('missing', S.fMissing);
  return '/api/books?' + p.toString();
}

async function loadAll(){
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
async function loadMoreBooks(){
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

function computeRows(){ return S.books; }

function reload(){ S.cursor = -1; S.nextPage = 1; S.books = []; loadAll(); }

function sortBy(col){
  if (S.sort.col === col) S.sort.dir = S.sort.dir==='asc' ? 'desc' : 'asc';
  else S.sort = { col, dir: 'asc' };
  reload();
}

// Debounced: every keystroke is a query on the server now, not a filter over an
// array already in memory.
let qTimer = null;
function setQ(v){
  S.q = v;
  clearTimeout(qTimer);
  qTimer = setTimeout(reload, 250);
}

function toggleTagFilter(id){
  S.fTag = S.fTag === id ? null : id;
  renderFilters(); reload();
}
function toggleUntagged(){
  S.fTag = S.fTag === 'untagged' ? null : 'untagged';
  renderFilters(); reload();
}
function toggleMissing(k){
  S.fMissing = S.fMissing === k ? null : k;
  renderFilters(); reload();
}
function clearFilters(){
  S.q=''; document.getElementById('q').value='';
  S.fTag=null; S.fMissing=null;
  renderFilters(); reload();
}

/// Shows a label only when the thing it labels exists — an empty console
/// otherwise reads as "Tags: Views:" with nothing after either.
function showLabelIf(id, hasContent){
  const el = document.getElementById(id);
  if (el) el.classList.toggle('hidden', !hasContent);
}

function renderFilters(){
  document.getElementById('tagfilters').innerHTML =
    S.groups.map(g=>`<button class="fchip ${S.fTag===g.id?'on':''}" data-act="tagfilter" data-id="${esc(g.id)}">${esc(g.name)}</button>`).join('')
    + `<button class="fchip ${S.fTag==='untagged'?'on':''}" onclick="toggleUntagged()">Untagged</button>`;
  document.getElementById('missingfilters').innerHTML =
    [['file','No file'],['cover','No cover'],['year','No year'],['author','No author']]
      .map(([k,l])=>`<button class="fchip ${S.fMissing===k?'on':''}" data-act="missing" data-key="${esc(k)}">${l}</button>`).join('');
}

// ---- table --------------------------------------------------------------

function arrow(col){ return S.sort.col===col ? (S.sort.dir==='asc'?' ▲':' ▼') : ''; }

function headHtml(){
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
      r += `<td class="actions">
        <button class="btn sm" data-act="openreader" data-book="${esc(b.id)}">Read</button>
        <button class="btn sm" data-act="pickupload" data-book="${esc(b.id)}">Upload</button>
        <button class="btn sm" data-act="openlink" data-book="${esc(b.id)}">Link</button>
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

function openImport(){
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

function importSource(which){
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

function importPickFile(){
  const i = document.createElement('input');
  i.type='file'; i.accept='.csv,.json,.txt,text/csv,application/json,text/plain';
  i.onchange = async ()=>{ const f=i.files[0]; if(!f) return;
    document.getElementById('imp-text').value = await f.text(); importScan(); };
  i.click();
}

function importPickFolder(){
  const i = document.createElement('input');
  i.type='file'; i.multiple = true; i.webkitdirectory = true;
  i.onchange = ()=> importScanFolder([...i.files]);
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

// The column aliases a real export actually uses, so a Goodreads or StoryGraph
// file imports without being edited first. Same list the app understands
// (docs/IMPORTING.md).
const IMP_COLS = {
  title:     ['title','name','book title'],
  subtitle:  ['subtitle'],
  authors:   ['author','authors','primary author'],
  year:      ['year','published_year','published','original publication year','first published'],
  publisher: ['publisher'],
  isbn:      ['isbn','isbn13','isbn_13','isbn/uid'],
  pages:     ['pages','page_count','number of pages'],
};

function splitAuthors(raw){
  return String(raw||'').split(/[;,]|\band\b|&/).map(s=>s.trim()).filter(Boolean);
}

function parseCatalogue(text){
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
function fromFilename(name){
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

async function sha256Of(file){
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

async function importScan(){
  const st = document.getElementById('imp-status');
  const parsed = parseCatalogue(document.getElementById('imp-text').value);
  if (parsed.error){ st.textContent = parsed.error; return; }
  st.textContent = 'Checking '+parsed.items.length+' row(s) against your library…';
  await importReview(parsed.items);
}

async function importScanFolder(files){
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
async function importReview(items){
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

function importRenderReview(){
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

function importToggle(i, on){ IMP.items[i].include = on; importCount(); }

function importCount(){
  const n = IMP.items.filter(x=>x.include).length;
  const btn = document.getElementById('imp-do');
  btn.disabled = n === 0;
  btn.textContent = n ? 'Import '+n : 'Import';
}

async function importDo(){
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
        ${OPT_COLS.map(([k,l])=>`<label><input type="checkbox" ${S.cols.has(k)?'checked':''} data-changeact="togglecol" data-key="${esc(k)}">${l}</label>`).join('')}
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

// `onCancel`, when given, adds a Stop button — a long bulk operation the user
// cannot stop is a long bulk operation they learn not to start.
function showProgress(label, onCancel){
  let el = document.getElementById('uprog');
  if (!el){
    el = document.createElement('div');
    el.id = 'uprog'; el.className = 'uprog';
    el.innerHTML = '<div class="uprog-label"></div><div class="uprog-track"><div class="uprog-bar"></div></div><div class="uprog-pct"></div><button class="btn sm uprog-cancel hidden">Stop</button>';
    document.body.appendChild(el);
  }
  el.querySelector('.uprog-label').textContent = label;
  el.querySelector('.uprog-bar').style.width = '0%';
  el.querySelector('.uprog-pct').textContent = '0%';
  const cancel = el.querySelector('.uprog-cancel');
  cancel.classList.toggle('hidden', !onCancel);
  cancel.onclick = onCancel || null;
  el.style.display = 'flex';
}
// `detail` names what is being worked on right now, so a stalled bulk run shows
// *which* book it stalled on.
function setProgress(fraction, detail){
  const el = document.getElementById('uprog'); if (!el) return;
  const pct = Math.round(fraction * 100);
  el.querySelector('.uprog-bar').style.width = pct + '%';
  el.querySelector('.uprog-pct').textContent = (pct >= 100 ? 'finishing…' : pct + '%');
  if (detail !== undefined){
    const label = el.querySelector('.uprog-label');
    label.textContent = label.textContent.split(' — ')[0] + (detail ? ' — ' + detail : '');
  }
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

// Cancellable, with per-item results (plan 5 #35). Fetching metadata for 500
// books used to be a spinner and hope: no way to know which ones failed, and no
// way to stop. The cancel flag is checked between books rather than mid-request,
// so a cancel never leaves a half-applied update.
let bulkCancelled = false;
function cancelBulk(){ bulkCancelled = true; toast('Stopping after this book…'); }

async function enrichSelected(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  const ids = [...S.selected];
  const byId = new Map(S.books.map(b=>[b.id, b.title]));
  bulkCancelled = false;
  showProgress('Fetching metadata…', cancelBulk);

  const failed = [];
  let done = 0, ok = 0;
  for (const id of ids){
    if (bulkCancelled) break;
    setProgress(done/ids.length, byId.get(id) || '');
    try { await api('POST','/api/books/'+id+'/enrich'); ok++; }
    catch(e){ failed.push({ title: byId.get(id) || id, error: e.message }); }
    done++;
  }
  hideProgress();
  await loadAll();

  if (!failed.length){
    toast(bulkCancelled
      ? `Stopped after ${done} of ${ids.length} — ${ok} updated`
      : `Fetched metadata for ${ok} book(s)`);
    return;
  }
  // Per-item results, because "3 failed" without naming them is unactionable.
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Fetched ${ok} of ${done}</h2>
      <p class="muted" style="margin:0 0 12px">These could not be looked up —
        usually no ISBN, or nothing matched.</p>
      <div style="max-height:50vh; overflow:auto">${
        failed.map(f=>`<div class="row" style="justify-content:space-between; gap:12px;
          padding:6px 0; border-bottom:1px solid var(--line)">
          <span>${esc(f.title)}</span>
          <span class="muted" style="font-size:12px">${esc(f.error)}</span></div>`).join('')
      }</div>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
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
  // Asked for rather than typed into a box that sat in the toolbar unused:
  // making a tag is occasional, and a permanent input for it is permanent
  // clutter.
  const name = (prompt('Name the new tag:', '') || '').trim();
  if (!name) return;
  try { await api('POST','/api/groups',{ name }); await loadAll(); toast('Tag created'); }
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

// One open detail panel's unsaved state. `pending` holds the fields a fetched
// match proposes that the panel has nowhere to type — publisher, ISBN, page
// count — so Save can write them and Cancel can drop them. `results` is the
// last search, so clicking a candidate can find it again.
let DETAIL = { id: null, pending: null, results: [] };

async function openDetail(id){
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

/// Save writes what the panel shows — the typed edits plus whatever a fetched
/// match proposed — and nothing else. Only *changed* fields go in the body: an
/// unchanged one would still bump `updated_at`, which is the clock every other
/// device pulls on.
async function saveDetail(id){
  const body = { ...(pendingDetailEdits() || {}), ...(DETAIL.pending || {}) };
  if ('title' in body && !body.title){ toast('Title cannot be empty'); return; }
  if (!Object.keys(body).length){ closeModal(); return; }
  try { await api('PATCH','/api/books/'+id, body); closeModal(); await loadAll(); toast('Saved'); }
  catch(e){ toast(e.message); }
}

/// True while the panel holds anything that pressing Cancel would throw away.
function detailIsDirty(){
  try { return !!(pendingDetailEdits() || DETAIL.pending); }
  catch(_){ return false; }          // panel already gone
}

/// Cancel is the way out that keeps nothing: the edits, and any fetched match
/// sitting in the form, are dropped. Confirmed only when there is something to
/// lose, so the ordinary "I just looked at it" close stays one click.
function cancelDetail(){
  if (detailIsDirty() && !confirm('Discard your changes to this book?')) return;
  DETAIL = { id: null, pending: null, results: [] };
  closeModal();
}

/// The fields edited in the detail panel but not yet saved, or null if none
/// are. `defaultValue` is what the input was rendered with, so this is a plain
/// comparison against the row as it was loaded — no separate copy to keep in
/// step.
function pendingDetailEdits(){
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
async function enrichFromDetail(id){
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
function pickDetailCandidate(i){
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
      <label>Password (optional)</label>
      <input type="text" id="m-pw" autocomplete="off" placeholder="Leave empty for a link that just opens">
      <p class="muted" style="margin:4px 0 0; font-size:.82rem">With a password
        set, the URL alone is not enough — useful for a link you send through a
        group chat. Send the password some other way.</p>
      <div id="m-out"></div>
      <div class="row">
        <button class="btn" onclick="closeModal()">Close</button>
        <button class="btn primary" id="m-create" data-act="createlink" data-book="${esc(bookId)}">Create link</button>
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
  // Shown in the clear rather than as a password field: whoever creates the
  // link has to read it back to pass it on, and hiding it from them protects
  // nobody.
  const pw = document.getElementById('m-pw').value.trim();
  try {
    const r = await api('POST','/api/share-links', {
      book_id: bookId, one_time: oneTime, ...(exp?{expires_at:exp}:{}),
      ...(pw?{password:pw}:{}),
    });
    const out = document.getElementById('m-out');
    out.innerHTML = `<label>Share this link</label>
      <div class="linkout" id="m-url">${esc(r.url)}</div>
      <div class="row"><button class="btn" data-act="copyurl" data-url="${esc(r.url)}">Copy</button></div>
      ${pw ? '<p class="muted" style="margin:8px 0 0; font-size:.82rem">Opening it ' +
             'needs the password you set. It is stored hashed — nothing here can show ' +
             'it again.</p>' : ''}`;
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
if (S.token) showApp(); else checkRegistration();


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

// Reading in the browser (plan 5 #33). A new tab, because reading and managing
// are different activities and losing your place in the table to skim a chapter
// is exactly the annoyance this would otherwise create.
function openReader(id){ window.open('/read/' + encodeURIComponent(id), '_blank', 'noopener'); }

// ---- borrow requests (plan 5 #49) ---------------------------------------

async function showRequests(){
  let incoming;
  try {
    incoming = await api('GET','/api/borrow-requests?direction=incoming');
  } catch(e){ toast(e.message); return; }

  const pending = incoming.filter(r => r.status === 'pending');
  const rows = pending.length ? pending.map(r => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span>
        <strong>${esc(r.book_title)}</strong>
        <span class="muted">· ${esc(r.requester_email)}</span>
        ${r.note ? `<div class="muted" style="font-size:12px">“${esc(r.note)}”</div>` : ''}
      </span>
      <span class="row" style="gap:6px">
        <button class="btn sm" data-act="decide" data-id="${esc(r.id)}" data-decision="declined">Decline</button>
        <button class="btn sm primary" data-act="decide" data-id="${esc(r.id)}" data-decision="approved">Lend it</button>
      </span>
    </div>`).join('')
    : '<p class="muted">Nobody is waiting on you.</p>';

  const answered = incoming.filter(r => r.status !== 'pending');
  const history = answered.length ? `
    <p class="muted" style="margin:14px 0 4px">Answered</p>` + answered.map(r => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:4px 0; font-size:13px">
      <span>${esc(r.book_title)} <span class="muted">· ${esc(r.requester_email)}</span></span>
      <span class="muted">${esc(r.status)}</span>
    </div>`).join('') : '';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(620px,95vw)">
      <h2 style="margin:0 0 4px">Borrow requests</h2>
      <p class="muted" style="margin:0 0 12px">Approving creates the loan —
        it appears under the book's copies with the due date you pick.</p>
      <div style="max-height:55vh; overflow:auto">${rows}${history}</div>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

async function decideRequest(id, status){
  const body = { status };
  if (status === 'approved'){
    // A date or nothing: "borrow it as long as you like" is a real
    // arrangement, and forcing a date would describe one nobody made.
    const raw = prompt('Due back on (YYYY-MM-DD), or leave blank for no date:', '');
    if (raw === null) return;
    if (raw.trim()) body.due_at = raw.trim() + ' 00:00:00';
  } else {
    const reply = prompt('Say why (optional):', '');
    if (reply === null) return;
    if (reply.trim()) body.reply = reply.trim();
  }
  try {
    await api('POST','/api/borrow-requests/' + id + '/decide', body);
  } catch(e){ toast(e.message); return; }
  toast(status === 'approved' ? 'Lent — the loan is recorded' : 'Answered');
  showRequests();
}

// ---- published rooms (plan 5 #47/#48) -----------------------------------

async function showRooms(){
  let rooms;
  try {
    rooms = await api('GET','/api/layouts');
  } catch(e){ toast(e.message); return; }

  const list = rooms.length ? rooms.map(r => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span><strong>${esc(r.name)}</strong>
        <span class="muted">· revision ${r.revision}${r.mine ? '' : ' · shared with you'}</span></span>
      <span class="row" style="gap:6px">
        <button class="btn sm" data-act="viewroom" data-id="${esc(r.id)}">View</button>
        ${r.mine ? `<button class="btn sm" data-act="shareroom" data-id="${esc(r.id)}" data-name="${esc(r.name)}">Public link</button>` : ''}
      </span>
    </div>`).join('')
    : '<p class="muted">No rooms have been published yet. Arrange one in the app and publish it.</p>';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Rooms</h2>
      <p class="muted" style="margin:0 0 12px">Published physical layouts. A room
        carries shelf and book positions only — never titles.</p>
      <div style="max-height:55vh; overflow:auto">${list}</div>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

// A public link to a room. The "show titles" tick is deliberately separate and
// off by default: sharing where the books *are* is not the same as saying what
// they are, and a link is the thing that can escape.
async function shareRoom(id, name){
  const showBooks = confirm(
    `Create a public link to “${name}”?\n\n` +
    'OK: also show the titles of the books you collected under its ' +
    '“Room: ' + name + '” tag.\n' +
    'Cancel this dialog and use it again if you only want the shapes.');
  let link;
  try {
    link = await api('POST','/api/share-links',
      { kind:'layout', layout_id:id, show_books: showBooks });
  } catch(e){ toast(e.message); return; }
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Public link</h2>
      <p class="muted" style="margin:0 0 12px">Anyone with this link can look at
        the room${showBooks ? ' and read the titles of its tagged books' : ' — the books show as blank spines'}.
        Revoke it from Links at any time.</p>
      <input readonly value="${esc(link.url)}" style="width:100%"
             onclick="this.select()">
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Done</button>
      </div>
    </div></div>`;
}


// ---- shares: everything this library has let out --------------------------
//
// One screen for both kinds, because "who can see my books" is one question:
// account shares (a person with a login) and public links (a URL). Links are
// listed whatever state they are in — live, expired, used up, revoked — since
// the useful question is usually "what did I share, and is it still open?",
// which a list of only-live links cannot answer.
//
// Account shares have no past tense to show: revoking one deletes the row, so
// what you see is what is current. The note in the screen says so rather than
// letting an empty section imply nobody was ever shared with.

function linkState(l){
  if (l.revoked) return { label:'Revoked', cls:'off' };
  if (l.expires_at && new Date(l.expires_at.replace(' ','T') + 'Z') <= new Date())
    return { label:'Expired', cls:'off' };
  if (l.max_uses !== null && l.use_count >= l.max_uses)
    return { label:'Used up', cls:'off' };
  return { label:'Live', cls:'on' };
}

function shareRow(s){
  const target = s.scope_label || s.scope;
  return `
    <div class="row shareline">
      <span>
        <strong>${esc(s.grantee_email)}</strong>
        <span class="muted"> · ${esc(s.permission)}</span>
        <div class="muted sharesub">${esc(target)} · shared by ${esc(s.owner_email)}
          · ${esc((s.created_at||'').slice(0,10))}</div>
      </span>
      <button class="btn sm danger" data-act="revokeshare" data-id="${esc(s.id)}">Revoke</button>
    </div>`;
}

function linkRow(l){
  const st = linkState(l);
  const uses = l.max_uses === null ? `${l.use_count} download${l.use_count===1?'':'s'}`
                                   : `${l.use_count} of ${l.max_uses} used`;
  const bits = [
    l.kind === 'layout' ? 'room' : 'book',
    esc((l.created_at||'').slice(0,10)),
    uses,
    l.expires_at ? 'expires ' + esc(l.expires_at.slice(0,10)) : 'no expiry',
  ];
  return `
    <div class="row shareline">
      <span>
        <strong>${esc(l.book_title)}</strong>
        ${l.has_password ? '<span class="pill">password</span>' : ''}
        <span class="pill ${st.cls}">${st.label}</span>
        <div class="muted sharesub">${bits.join(' · ')}</div>
      </span>
      ${st.label === 'Live'
        ? `<button class="btn sm danger" data-act="revokelink" data-id="${esc(l.id)}">Revoke</button>`
        : '<span class="muted sharesub">closed</span>'}
    </div>`;
}

async function showShares(){
  let shares = [], links = [];
  try {
    [shares, links] = await Promise.all([
      api('GET','/api/shares'),
      api('GET','/api/share-links'),
    ]);
  } catch(e){ toast(e.message); return; }

  const live = links.filter(l => linkState(l).label === 'Live').length;
  const linkList = links.length
    ? links.map(linkRow).join('')
    : '<p class="muted">No public links have been made.</p>';
  const shareList = shares.length
    ? shares.map(shareRow).join('')
    : '<p class="muted">Nobody with an account has been given access.</p>';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(720px,95vw)">
      <h2 style="margin:0 0 4px">Shares</h2>
      <p class="muted" style="margin:0 0 14px">Everything this library has let
        out: ${live} live link${live===1?'':'s'} of ${links.length}, and
        ${shares.length} account share${shares.length===1?'':'s'}.</p>

      <p class="sharehead">Public links</p>
      <p class="muted sharesub" style="margin:0 0 8px">Anyone holding the URL,
        no account needed. Kept after they close so you can see what was shared.</p>
      <div style="max-height:34vh; overflow:auto">${linkList}</div>

      <p class="sharehead" style="margin-top:16px">People with accounts</p>
      <p class="muted sharesub" style="margin:0 0 8px">Current only — revoking
        one removes the record with it.</p>
      <div style="max-height:26vh; overflow:auto">${shareList}</div>

      <div class="row" style="justify-content:flex-end; margin-top:14px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

async function revokeLink(id){
  if (!confirm('Revoke this link? Anyone holding the URL loses access at once.')) return;
  try { await api('DELETE','/api/share-links/' + encodeURIComponent(id)); }
  catch(e){ toast(e.message); return; }
  toast('Link revoked');
  showShares();
}

async function revokeShare(id){
  if (!confirm('Revoke this share? They lose access to what it covered.')) return;
  try { await api('DELETE','/api/shares/' + encodeURIComponent(id)); }
  catch(e){ toast(e.message); return; }
  toast('Share revoked');
  showShares();
}

// ---- saved views (plan 5 #35) -------------------------------------------
//
// A view is a name for "how I like to look at the library": the search text,
// the tag and missing filters, the sort, and which columns are shown. Kept in
// localStorage rather than on the server on purpose — it is a *browser*
// preference, like the density toggle, and putting it on the server would mean
// a schema, an endpoint and a sync story for something nobody shares.

function savedViews(){
  try { return JSON.parse(localStorage.getItem('vellum_views') || '[]'); }
  catch(_){ return []; }
}

function saveView(){
  const name = (prompt('Name this view') || '').trim();
  if (!name) return;
  const views = savedViews().filter(v => v.name !== name); // overwrite by name
  views.push({
    name,
    q: S.q, sort: { ...S.sort }, tag: S.fTag, missing: S.fMissing,
    cols: [...S.cols],
  });
  localStorage.setItem('vellum_views', JSON.stringify(views));
  renderViews();
  toast('Saved “' + name + '”');
}

function applyView(name){
  const view = savedViews().find(v => v.name === name);
  if (!view) return;
  S.q = view.q || '';
  document.getElementById('q').value = S.q;
  S.sort = view.sort || { col:'title', dir:'asc' };
  S.fTag = view.tag || null;
  S.fMissing = view.missing || null;
  if (view.cols) { S.cols = new Set(view.cols); localStorage.setItem('vellum_cols', JSON.stringify([...S.cols])); }
  renderFilters(); renderViews(); reload();
}

function deleteView(name){
  localStorage.setItem('vellum_views',
    JSON.stringify(savedViews().filter(v => v.name !== name)));
  renderViews();
}

function renderViews(){
  const host = document.getElementById('views');
  if (!host) return;
  const views = savedViews();
  // No saved views means no "Views:" label — it would introduce a heading for
  // an empty space, which is how the filter row came to look busy.
  showLabelIf('viewslabel', views.length > 0);
  host.innerHTML = views.map(v =>
    `<span class="fchip">
       <span class="link" data-act="applyview" data-name="${esc(v.name)}">${esc(v.name)}</span>
       <button title="Forget this view" data-act="deleteview" data-name="${esc(v.name)}">×</button>
     </span>`).join('');
}

// ---- activity log (plan 5 #35) ------------------------------------------

async function showActivity(before){
  let body;
  try {
    body = await api('GET','/api/admin/audit?limit=100' + (before ? '&before='+before : ''));
  } catch(e){
    toast(/master/.test(e.message)
      ? 'Only the library owner can read the activity log.'
      : e.message);
    return;
  }
  if (!body.enabled){
    toast('The activity log is off on this server (set VELLUM_AUDIT=1).');
    return;
  }
  const rows = (body.rows||[]).map(r => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:6px 0; border-bottom:1px solid var(--line)">
      <span><strong>${esc(r.action)}</strong>
        ${r.detail ? '· ' + esc(r.detail) : ''}</span>
      <span class="muted" style="font-size:12px; white-space:nowrap">
        ${esc(r.actor_email || 'unknown')} · ${esc((r.at||'').replace('T',' '))}</span>
    </div>`).join('') || '<p class="muted">Nothing recorded yet.</p>';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(720px,95vw)">
      <h2 style="margin:0 0 4px">Activity</h2>
      <p class="muted" style="margin:0 0 12px">Who changed what on this server.
        The oldest entries are trimmed automatically.</p>
      <div style="max-height:60vh; overflow:auto">${rows}</div>
      <div class="row" style="justify-content:space-between; margin-top:12px">
        ${body.next_before
          ? `<button class="btn" data-act="activity" data-before="${esc(body.next_before ?? '')}">Older</button>`
          : '<span></span>'}
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
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


// ---- people (plan 6 #1) ---------------------------------------------------
//
// Administering the accounts in a shared library. Master-only, and the only
// place it exists: creating a second user used to mean hand-crafting an
// authenticated HTTP request, which made every sharing feature unreachable in
// practice.
//
// Inviting is preferred over creating with a password. An invite lets the
// person choose their own, and never puts a password the admin knows into the
// database — the same reasoning as the reset flow.

async function showPeople(){
  let users, invites;
  try {
    users = await api('GET','/api/users');
  } catch(e){
    toast(/master/.test(e.message)
      ? 'Only the library owner can manage people.'
      : e.message);
    return;
  }
  // Invites need SMTP to be *sent*, but the list works regardless — a server
  // without mail still mints links to pass along by hand.
  try { invites = await api('GET','/api/invites'); } catch(e){ invites = []; }

  const rows = users.map(u => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span>
        <strong>${esc(u.display_name || u.email)}</strong>
        ${u.is_master ? '<span class="muted"> · owner</span>' : ''}
        <div class="muted" style="font-size:12px">${esc(u.email)}</div>
      </span>
      <span class="row" style="gap:6px">
        <button class="btn sm" data-act="setrole" data-id="${esc(u.id)}" data-master="${u.is_master ? '0' : '1'}">
          ${u.is_master ? 'Make member' : 'Make owner'}</button>
        <button class="btn sm" data-act="resetfor" data-email="${esc(u.email)}">Send reset</button>
        <button class="btn sm danger" data-act="removeperson" data-id="${esc(u.id)}" data-email="${esc(u.email)}">
          Remove</button>
      </span>
    </div>`).join('');

  const pending = invites.length ? `
    <p class="muted" style="margin:14px 0 4px">Invited, not yet joined</p>` +
    invites.map(i => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:6px 0; font-size:13px">
      <span>${esc(i.email)}
        <span class="muted">· ${esc(i.permission)}${i.scope ? ' · ' + esc(i.scope) : ''}</span>
      </span>
      <button class="btn sm" data-act="revokeinvite" data-id="${esc(i.id)}">Withdraw</button>
    </div>`).join('') : '';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(680px,95vw)">
      <h2 style="margin:0 0 4px">People</h2>
      <p class="muted" style="margin:0 0 12px">Everyone with an account on this
        server. An owner can manage people and see the whole library; a member
        sees only what has been shared with them.</p>
      <div style="max-height:50vh; overflow:auto">${rows}${pending}</div>
      <div class="row" style="gap:8px; margin-top:14px; align-items:flex-end">
        <div class="group" style="flex:1">
          <input id="inv-email" type="text" placeholder="Email to invite"
                 style="width:100%" autocomplete="off">
        </div>
        <select id="inv-perm">
          <option value="viewer">Can read</option>
          <option value="editor">Can edit</option>
        </select>
        <button class="btn primary" onclick="invitePerson()">Invite</button>
      </div>
      <p class="muted" style="font-size:12px; margin:8px 0 0">
        They choose their own password. Without SMTP configured the link is
        shown here to pass along yourself.</p>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

async function setRole(id, isMaster){
  try {
    await api('PUT','/api/users/'+id, { is_master: isMaster });
    toast(isMaster ? 'Now an owner.' : 'Now a member.');
    showPeople();
  } catch(e){ toast(e.message); }
}

// Removing an account is the one action here that destroys something, so it
// says exactly what goes: the cascade takes their highlights, sittings, notes
// and shares, and leaves the books.
async function removePerson(id, email){
  if (!confirm(
    'Remove ' + email + '?\n\n' +
    "Their highlights, notes, reading history and shares go with them. " +
    'Books they added stay in the library.')) return;
  try {
    await api('DELETE','/api/users/'+id);
    toast('Removed.');
    showPeople();
  } catch(e){ toast(e.message); }
}

async function invitePerson(){
  const email = document.getElementById('inv-email').value.trim();
  if (!email) { toast('An email is needed.'); return; }
  const permission = document.getElementById('inv-perm').value;
  try {
    const res = await api('POST','/api/invites',
      { email, scope: 'all', permission });
    // `url` comes back only when the server couldn't email it.
    if (res && res.url) prompt('Send them this link:', res.url);
    else toast('Invitation sent.');
    showPeople();
  } catch(e){ toast(e.message); }
}

async function revokeInvite(id){
  try {
    await api('DELETE','/api/invites/'+encodeURIComponent(id));
    showPeople();
  } catch(e){ toast(e.message); }
}

async function resetFor(email){
  try {
    await api('POST','/api/auth/forgot', { email });
    toast('If mail is configured, a reset link is on its way.');
  } catch(e){ toast(e.message); }
}


// ---- menus (plan 6 #7) ----------------------------------------------------
//
// The console had twenty-odd controls above the table, most of them doing
// nothing until something was selected. They live in two menus now, and the
// selection-dependent ones only exist while there is a selection.

function toggleMenu(event, id){
  event.stopPropagation();
  const menu = document.getElementById(id);
  const wasOpen = !menu.classList.contains('hidden');
  closeMenus();
  if (!wasOpen) menu.classList.remove('hidden');
}

function closeMenus(){
  for (const m of document.querySelectorAll('.menu')) m.classList.add('hidden');
}

/// Runs a menu item and closes the menu — every item wants both, and forgetting
/// the second half leaves the menu hanging over whatever it just opened.
function pick(fn){
  closeMenus();
  fn();
}

document.addEventListener('click', closeMenus);
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeMenus(); });

/// The bar that appears when rows are selected. Rebuilt on every render so the
/// count is honest and the tag list matches the tags that currently exist.
function renderSelectionBar(){
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

function clearSelection(){ S.selected.clear(); render(); }

/// Keeps the sticky table head directly under the chrome.
///
/// It used to be a hard-coded 150px, which was fine when the toolbars were a
/// fixed stack. The chrome now grows and shrinks — the selection bar comes and
/// goes, and rows wrap on a narrow window — so the offset is measured instead
/// of guessed, or the head floats over the toolbar or leaves a gap under it.
function syncStickyHead(){
  const bar = document.getElementById('topbar');
  if (!bar) return;
  document.documentElement.style.setProperty(
    '--thead-top', bar.getBoundingClientRect().height + 'px');
}
addEventListener('resize', syncStickyHead);
