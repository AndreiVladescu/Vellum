// Bulk edit and bulk delete of the selected rows.

import { S } from './state.js';
import { toast } from './dom.js';
import { api } from './api.js';
import { ask, closeModal } from './dialogs.js';
import { loadAll } from './books.js';

// ---- bulk edit + delete -------------------------------------------------

export function openBulkEdit(){
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
export async function bulkEditApply(){
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

export async function deleteSelected(){
  if (S.selected.size===0) return;
  if (!await ask({
    title: `Delete ${S.selected.size} book${S.selected.size===1?'':'s'}?`,
    body: 'Their files go too. This cannot be undone.',
    confirmLabel: 'Delete',
    danger: true,
  })) return;
  try { for (const id of S.selected) await api('DELETE', `/api/books/${id}`);
        S.selected.clear(); await loadAll(); toast('Deleted'); }
  catch(e){ toast(e.message); }
}
