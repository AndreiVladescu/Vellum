// The activity (audit) log.

import { esc, toast } from './dom.js';
import { api } from './api.js';

// ---- activity log (plan 5 #35) ------------------------------------------

export async function showActivity(before){
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
