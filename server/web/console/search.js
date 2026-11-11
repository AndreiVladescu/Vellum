// Searching inside the books (content search).

import { esc, toast } from './dom.js';
import { api } from './api.js';

// ---- content search (plan 5 #32) ----------------------------------------
//
// Searching the *text* of the books, which only a server can do. The button is
// revealed by the capability handshake rather than by trying and failing.

export async function revealContentSearch(){
  try {
    const caps = await api('GET','/api/capabilities');
    if (!(caps.features||[]).includes('content_search')) return;
  } catch(e){ return; }
  document.getElementById('contentbtn').classList.remove('hidden');
  document.getElementById('contentsep').classList.remove('hidden');
}

export async function searchContents(){
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
