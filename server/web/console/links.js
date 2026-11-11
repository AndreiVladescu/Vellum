// Public links for one book, and opening the browser reader.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { download } from './export.js';

// ---- public links (unchanged) -------------------------------------------

export function openLink(bookId){
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

export async function createLink(bookId){
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
export function copyUrl(url){ navigator.clipboard.writeText(url).then(()=>toast('Copied')); }

// Reading in the browser (plan 5 #33). A new tab, because reading and managing
// are different activities and losing your place in the table to skim a chapter
// is exactly the annoyance this would otherwise create.
// The token rides the URL fragment for the same reason viewroom's does — see
// that comment above and the matching one in read.js.
export function openReader(id){
  window.open(
    '/read/' + encodeURIComponent(id) + '#t=' + encodeURIComponent(S.token),
    '_blank', 'noopener',
  );
}
