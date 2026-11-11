// The server statistics page.

import { esc, toast } from './dom.js';
import { api } from './api.js';

// ---- Server dashboard (plan 5 #37) ----------------------------------------
// Deliberately small: for a personal server, "how big is my library and how much
// disk is it using" is the question an operator actually has, and a metrics
// stack would be more machinery than the thing it observes.
export function fmtBytes(n){
  if (!n) return '0 B';
  const units = ['B','KB','MB','GB','TB'];
  let i = 0, v = n;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(1)) + ' ' + units[i];
}

export async function showStats(){
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
