// Published rooms and their public links.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';

// ---- published rooms (plan 5 #47/#48) -----------------------------------

export async function showRooms(){
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
export async function shareRoom(id, name){
  // This was a `confirm()` whose Cancel button did not cancel: it made the
  // link anyway, without titles. Two outcomes crammed into OK/Cancel, and the
  // third — "actually, no link" — had nowhere to go.
  const answer = await ask({
    title: `Public link to “${name}”`,
    body: 'Anyone with the URL can look at the room, without an account.',
    fields: [{
      label: 'What it shows',
      value: 'shapes',
      options: [
        { value: 'shapes', label: 'The shelves and shapes only' },
        { value: 'titles', label: 'Shapes and the titles of its tagged books' },
      ],
      hint: 'Books collected under the room’s own tag.',
    }],
    confirmLabel: 'Create link',
  });
  if (!answer) return;
  const showBooks = answer[0] === 'titles';
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
