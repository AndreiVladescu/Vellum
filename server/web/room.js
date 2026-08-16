// The room viewer (plan 5 #48).
//
// Renders a published `layout_doc` as inline SVG: shelf lines and one rectangle
// per placed book. No library — a room is rectangles, and pulling in a rendering
// dependency for rectangles would be the wrong trade twice over (bundle size,
// and the CSP forbids a CDN anyway).
//
// **Redaction is structural.** The document carries geometry only, so a book the
// viewer isn't allowed to see has no title *in the data*. Titles arrive from a
// separate, RBAC-filtered request; a spine with no entry there is simply drawn
// blank. There is no filtering step to forget.

const PATH = location.pathname.split('/').filter(Boolean);
// '/room/<layout id>' signed in, '/pr/<token>' for a public link.
const MODE = PATH[0] === 'pr' ? 'link' : 'room';
const KEY = decodeURIComponent(PATH[1] || '');

// sessionStorage isn't shared with a tab window.open() creates for a
// different URL — only the console's own tab has the console's token. The
// console hands it to this new tab via the URL fragment instead (never sent
// to the server, unlike a query string, so it never reaches an access log);
// consumed once into this tab's own sessionStorage and then scrubbed from
// the address bar so it doesn't linger there. Without this, every room
// opened from the console 401ed with "sign in to the console first" — even
// signed in, in the tab right next to it.
if (MODE === 'room' && location.hash.startsWith('#t=')) {
  sessionStorage.setItem('vellum_token', decodeURIComponent(location.hash.slice(3)));
  history.replaceState(null, '', location.pathname);
}
const TOKEN = MODE === 'room' ? sessionStorage.getItem('vellum_token') : null;

const S = { doc: null, books: new Map(), view: null };

function headers(){ return TOKEN ? { authorization: 'Bearer ' + TOKEN } : {}; }
function esc(s){ return (s ?? '').toString().replace(/[&<>"']/g,
  c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

async function getJson(path){
  const res = await fetch(path, { headers: headers() });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res.json();
}

// A password-protected room link answers 401 until the unlock cookie exists.
// This page is the entry point for such a link — there is no earlier screen to
// have typed it on — so it asks here.
function askPassword(message){
  const stage = document.getElementById('stage');
  stage.innerHTML =
    '<form id="lock" class="lock">' +
      '<p>This link has a password.</p>' +
      '<input id="pw" type="password" placeholder="Password" aria-label="Password" ' +
             'autocomplete="current-password">' +
      '<button class="btn" type="submit">Open</button>' +
      (message ? '<p class="err">' + esc(message) + '</p>' : '') +
    '</form>';
  document.getElementById('pw').focus();
  document.getElementById('lock').addEventListener('submit', async (e) => {
    e.preventDefault();
    const res = await fetch('/api/public/' + encodeURIComponent(KEY) + '/unlock', {
      method:'POST', headers:{'content-type':'application/json'},
      body: JSON.stringify({ password: document.getElementById('pw').value }),
    });
    if (res.ok) { start(); return; }
    const body = await res.json().catch(() => ({}));
    askPassword(body.error || 'That did not work.');
  });
}

function fail(message){
  document.getElementById('stage').innerHTML = `<p class="err">${message}</p>`;
  document.getElementById('title').textContent = 'Room';
}

async function start(){
  try {
    if (MODE === 'link'){
      const body = await getJson('/api/public/' + encodeURIComponent(KEY) + '/room');
      S.doc = body.doc;
      document.getElementById('title').textContent = body.name || 'Room';
      for (const b of body.books || []) S.books.set(b.book_id, b);
    } else {
      const layout = await getJson('/api/layouts/' + encodeURIComponent(KEY));
      S.doc = layout.doc;
      document.getElementById('title').textContent = layout.name || 'Room';
      // A second request, deliberately: the document is the same bytes for
      // everyone, and who may see which title is resolved server-side here.
      const books = await getJson('/api/layouts/' + encodeURIComponent(KEY) + '/books');
      for (const b of books) S.books.set(b.book_id, b);
    }
  } catch(e){
    if (MODE === 'link' && /\b401\b/.test(e.message)) { askPassword(); return; }
    fail(MODE === 'link'
      ? 'This link is no longer available.'
      : 'Could not open that room — sign in to the console first.');
    return;
  }
  if (!S.doc || !Array.isArray(S.doc.placements)){
    fail('That room has nothing in it yet.');
    return;
  }
  render();
  fit();
}

/// World bounds of everything in the document, with a little air around it.
function bounds(){
  let minX = Infinity, maxX = -Infinity, minY = 0, maxY = -Infinity;
  const see = (x, y) => {
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  };
  for (const s of S.doc.shelves || []){ see(s.x1, s.y1); see(s.x2, s.y2); }
  for (const p of S.doc.placements){
    const w = p.rotation === 90 ? p.height_m : p.width_m;
    const h = p.rotation === 90 ? p.width_m : p.height_m;
    see(p.x, p.y); see(p.x + w, p.y + h);
  }
  if (!isFinite(minX)) { minX = 0; maxX = 2; maxY = 2; }
  const pad = 0.15;
  return { x: minX - pad, y: minY - pad,
           w: (maxX - minX) + pad * 2, h: (maxY - minY) + pad * 2 };
}

// A deterministic colour per book, so the same spine looks the same on every
// visit and two adjacent books rarely match. Mirrors the app's generated-spine
// idea without sharing its palette code.
function spineColour(id){
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) | 0;
  const hue = Math.abs(hash) % 360;
  return `hsl(${hue} 28% 42%)`;
}

function render(){
  const b = bounds();
  const parts = [];

  for (const s of S.doc.shelves || []){
    // World Y is up; SVG Y is down, so the whole scene is flipped once here
    // rather than at every coordinate.
    //
    // Furniture (plan 5 #29) draws fainter than a shelf, and a bare label draws
    // no line at all — a side panel rendered as a plank reads as a shelf you
    // could put books on, which is the opposite of what it is. An older
    // document with no `kind` is all shelves, which is what it was published as.
    const kind = s.kind || 'shelf';
    if (kind !== 'label'){
      const cls = kind === 'shelf' ? 'plank' : 'plank structure';
      parts.push(`<line class="${cls}" x1="${s.x1}" y1="${-s.y1}" x2="${s.x2}" y2="${-s.y2}"/>`);
    }
    if (s.label){
      parts.push(`<text class="shelf-label" x="${Math.min(s.x1, s.x2)}" ` +
        `y="${-Math.max(s.y1, s.y2) - 0.03}" font-size="0.06">${esc(s.label)}</text>`);
    }
  }

  for (const p of S.doc.placements){
    const w = p.rotation === 90 ? p.height_m : p.width_m;
    const h = p.rotation === 90 ? p.width_m : p.height_m;
    const known = S.books.get(p.book_id);
    const fill = known ? spineColour(p.book_id) : 'var(--line)';
    const label = known
      ? `${known.title}${known.authors && known.authors.length ? ' — ' + known.authors.join(', ') : ''}`
      : 'A book you can’t see';
    const click = known && MODE === 'room'
      ? ` style="cursor:pointer" onclick="openBook('${esc(p.book_id)}')"`
      : '';
    parts.push(
      `<rect class="spine${known ? '' : ' anon'}" x="${p.x}" y="${-(p.y + h)}" ` +
      `width="${w}" height="${h}" fill="${fill}" rx="0.002"${click}>` +
      `<title>${esc(label)}</title></rect>`);
  }

  document.getElementById('stage').innerHTML =
    `<svg id="svg" viewBox="${b.x} ${-(b.y + b.h)} ${b.w} ${b.h}" ` +
    `preserveAspectRatio="xMidYMid meet">${parts.join('')}</svg>`;
  S.view = { x: b.x, y: -(b.y + b.h), w: b.w, h: b.h };

  const total = S.doc.placements.length;
  const named = S.doc.placements.filter(p => S.books.has(p.book_id)).length;
  document.getElementById('count').textContent =
    `${total} book${total === 1 ? '' : 's'}`;
  document.getElementById('note').textContent = named === total
    ? 'Hover a spine for its title.'
    : `${total - named} of these are shown without a title — you don’t have ` +
      'access to them, and the room itself never carried one.';
}

// Same token-in-fragment handoff as the console's own links to this page —
// only reachable when MODE === 'room', where TOKEN is guaranteed set (see top).
function openBook(id){
  window.open(
    '/read/' + encodeURIComponent(id) + '#t=' + encodeURIComponent(TOKEN),
    '_blank', 'noopener',
  );
}

function apply(){
  const svg = document.getElementById('svg');
  if (svg) svg.setAttribute('viewBox',
    `${S.view.x} ${S.view.y} ${S.view.w} ${S.view.h}`);
}

function fit(){ render(); }

function zoom(factor){
  // Around the centre, so pressing + doesn't walk the room off the screen.
  const cx = S.view.x + S.view.w / 2, cy = S.view.y + S.view.h / 2;
  S.view.w *= factor; S.view.h *= factor;
  S.view.x = cx - S.view.w / 2; S.view.y = cy - S.view.h / 2;
  apply();
}

document.getElementById('fit').onclick = fit;
document.getElementById('zin').onclick = () => zoom(1 / 1.25);
document.getElementById('zout').onclick = () => zoom(1.25);

// Drag to pan, wheel to zoom — in world units, so panning feels the same at
// every zoom level.
const stage = document.getElementById('stage');
let dragging = null;
stage.addEventListener('pointerdown', (e) => {
  if (!S.view) return;
  dragging = { x: e.clientX, y: e.clientY, view: { ...S.view } };
  stage.classList.add('dragging');
  stage.setPointerCapture(e.pointerId);
});
stage.addEventListener('pointermove', (e) => {
  if (!dragging) return;
  const rect = stage.getBoundingClientRect();
  S.view.x = dragging.view.x - (e.clientX - dragging.x) * (S.view.w / rect.width);
  S.view.y = dragging.view.y - (e.clientY - dragging.y) * (S.view.h / rect.height);
  apply();
});
for (const event of ['pointerup', 'pointercancel', 'pointerleave']){
  stage.addEventListener(event, () => { dragging = null; stage.classList.remove('dragging'); });
}
stage.addEventListener('wheel', (e) => {
  if (!S.view) return;
  e.preventDefault();
  zoom(e.deltaY < 0 ? 1 / 1.12 : 1.12);
}, { passive: false });

start();
