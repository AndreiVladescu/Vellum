// Reading a book in the browser (plan 5 #33).
//
// Two shapes behind one page:
//   /read/<book id>     — a signed-in console reader, bearer token from session
//   /r/<share token>    — anyone with a link, no account, no download
//
// EPUB sections arrive as *server-sanitised* HTML (see blobs::sanitize_html);
// PDF pages arrive as rendered JPEGs. Nothing here parses a book format, which
// is why the page needs no library.

const PATH = location.pathname.split('/').filter(Boolean);
// '/read/<id>' when signed in, '/r/<token>' for a share link.
const MODE = PATH[0] === 'r' ? 'link' : 'book';
const KEY = decodeURIComponent(PATH[1] || '');
const BASE = MODE === 'link' ? `/api/public/${encodeURIComponent(KEY)}/read`
                             : `/api/books/${encodeURIComponent(KEY)}/read`;

// The console keeps its bearer token in sessionStorage (plan 5 #35); a share
// link needs none, which is the whole point of the read-only mode. But
// sessionStorage isn't shared with a tab window.open() creates for a
// different URL, so a book opened from the console arrives here with none —
// the console hands it over via the URL fragment instead (never sent to the
// server, unlike a query string), consumed once and then scrubbed from the
// address bar. See the matching comment in room.js.
if (MODE === 'book' && location.hash.startsWith('#t=')) {
  sessionStorage.setItem('vellum_token', decodeURIComponent(location.hash.slice(3)));
  history.replaceState(null, '', location.pathname);
}
const TOKEN = MODE === 'book' ? sessionStorage.getItem('vellum_token') : null;

// Where you were, per book, in *this browser*. Deliberately not #5's
// cross-device channel: that is the app's reading position, tied to an account
// and an opt-in, and a browser skim should not overwrite it.
const POS_KEY = 'vellum_read_' + MODE + '_' + KEY;

const S = { manifest: null, index: 0 };

function headers(){ return TOKEN ? { authorization: 'Bearer ' + TOKEN } : {}; }

async function getJson(path){
  const res = await fetch(path, { headers: headers() });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res.json();
}

function fail(message){
  document.getElementById('content').innerHTML =
    `<p class="err">${message}</p>`;
  document.getElementById('progress').textContent = '';
}

async function start(){
  let manifest;
  try {
    manifest = await getJson(BASE);
  } catch(e){
    fail(MODE === 'book'
      ? 'Could not open that book — sign in to the console first.'
      : 'This link is no longer available.');
    return;
  }
  S.manifest = manifest;
  document.getElementById('title').textContent = manifest.title || 'Reading';

  if (manifest.kind === 'none' || !manifest.units){
    fail('There is no readable file for this book yet.');
    return;
  }

  if (manifest.downloadable && MODE === 'book'){
    // Only for a signed-in reader: a share link is read-only on purpose.
    const a = document.getElementById('download');
    a.classList.remove('hidden');
    a.onclick = (e) => { e.preventDefault(); downloadBook(); };
  }

  const jump = document.getElementById('jump');
  jump.classList.remove('hidden');
  jump.innerHTML = Array.from({ length: manifest.units }, (_, i) =>
    `<option value="${i}">${manifest.kind === 'pdf' ? 'Page ' + (i+1) : 'Section ' + (i+1)}</option>`
  ).join('');
  jump.onchange = () => show(Number(jump.value));

  const saved = Number(localStorage.getItem(POS_KEY) || 0);
  show(Number.isFinite(saved) && saved < manifest.units ? saved : 0);
}

async function show(index){
  const { units, kind } = S.manifest;
  S.index = Math.max(0, Math.min(units - 1, index));
  localStorage.setItem(POS_KEY, String(S.index));

  const content = document.getElementById('content');
  document.getElementById('jump').value = String(S.index);
  document.getElementById('prev').disabled = S.index === 0;
  document.getElementById('next').disabled = S.index >= units - 1;
  document.getElementById('progress').textContent =
    `${S.index + 1} of ${units}`;

  if (kind === 'pdf'){
    // The token can't ride an <img src>, so the page is fetched and shown as an
    // object URL — the same trick the console uses for covers.
    content.innerHTML = '<p class="muted">Rendering…</p>';
    try {
      const res = await fetch(`${BASE}/${S.index}`, { headers: headers() });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const url = URL.createObjectURL(await res.blob());
      const img = document.createElement('img');
      img.className = 'page';
      img.alt = `Page ${S.index + 1}`;
      img.addEventListener('load', () => URL.revokeObjectURL(url), { once: true });
      img.src = url;
      content.replaceChildren(img);
    } catch(e){
      content.innerHTML = '<p class="err">That page could not be rendered.</p>';
    }
    window.scrollTo(0, 0);
    return;
  }

  content.innerHTML = '<p class="muted">Loading…</p>';
  try {
    const section = await getJson(`${BASE}/${S.index}`);
    // Already sanitised server-side by an allowlist; assigning it here is the
    // point of doing that work there rather than trusting the book.
    content.innerHTML = section.html || '';
    document.getElementById('where').textContent = section.title || '';
    // The section's own <img src="asset/…"> paths are relative to this page's
    // URL, which is not where the API lives — rewrite them to the API base.
    for (const img of content.querySelectorAll('img[src^="asset/"]')){
      const rel = img.getAttribute('src');
      img.removeAttribute('src');
      fetch(`${BASE}/${rel}`, { headers: headers() })
        .then(r => r.ok ? r.blob() : Promise.reject())
        .then(blob => {
          const url = URL.createObjectURL(blob);
          img.addEventListener('load', () => URL.revokeObjectURL(url), { once: true });
          img.src = url;
        })
        .catch(() => img.remove());
    }
  } catch(e){
    content.innerHTML = '<p class="err">That section could not be loaded.</p>';
  }
  window.scrollTo(0, 0);
}

async function downloadBook(){
  try {
    const res = await fetch(`/api/books/${encodeURIComponent(KEY)}/files`,
                            { headers: headers() });
    const files = await res.json();
    if (!files.length) return;
    const file = files[0];
    const blob = await fetch('/api/files/' + file.id, { headers: headers() })
      .then(r => r.blob());
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = (S.manifest.title || 'book') + '.' + file.format;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  } catch(e){ /* the reader still works; the download simply didn't happen */ }
}

document.getElementById('prev').onclick = () => show(S.index - 1);
document.getElementById('next').onclick = () => show(S.index + 1);
// Arrow keys, because that is how people turn pages.
document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'SELECT') return;
  if (e.key === 'ArrowLeft') show(S.index - 1);
  if (e.key === 'ArrowRight' || e.key === ' ') show(S.index + 1);
});

start();
