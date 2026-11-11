// Tags: creating them and adding/removing them per book or in bulk.

import { S } from './state.js';
import { esc, key, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { loadAll } from './books.js';

// ---- tags ---------------------------------------------------------------

export async function createTag(){
  // Asked for rather than typed into a box that sat in the toolbar unused:
  // making a tag is occasional, and a permanent input for it is permanent
  // clutter.
  const answer = await ask({
    title: 'New tag',
    fields: [{ label: 'Name', placeholder: 'Technical' }],
    confirmLabel: 'Create',
  });
  const name = answer ? answer[0] : '';
  if (!name) return;
  try { await api('POST','/api/groups',{ name }); await loadAll(); toast('Tag created'); }
  catch(e){ toast(e.message); }
}

export async function addMember(groupId, bookId){
  if (S.members.has(key(groupId,bookId))) return;
  await api('POST', `/api/groups/${groupId}/books`, { book_id: bookId });
}
export async function removeTag(groupId, bookId){
  try { await api('DELETE', `/api/groups/${groupId}/books/${bookId}`); await loadAll(); }
  catch(e){ toast(e.message); }
}

export async function bulkTag(add){
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

export function quickAdd(btn, bookId){
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
