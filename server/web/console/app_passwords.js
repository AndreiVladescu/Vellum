// App passwords: a password per e-reader, so the account password is never
// typed into a Kindle.
//
// Every account has this page, not just the owner: each person manages their
// own devices and nobody else's. The server keeps only a hash, so a secret is
// shown exactly once, in the dialog that creates it; the list can say which
// one is which (its first four characters) but never show one again.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask, closeModal } from './dialogs.js';
import { openPage } from './pages.js';

/// The catalogue's address, for the setup instructions. `location` is the
/// console's own origin, which is the address this person reached the server
/// by — the one their e-reader on the same network should use too.
function appPasswordOpdsUrl(){
  const origin = typeof location !== 'undefined' && location.origin ? location.origin : '';
  return origin + '/opds';
}

/// `2026-11-13 09:41:07` (UTC, as SQLite stores it) → `2026-11-13 09:41`.
function appPasswordTime(s){ return esc((s || '').slice(0, 16)); }

export function appPasswordRow(p){
  const used = p.last_used_at ? 'last used ' + appPasswordTime(p.last_used_at) : 'never used';
  return `
    <div class="row shareline">
      <span>
        <strong>${esc(p.label)}</strong>
        <span class="pill">${esc(p.prefix)}-…</span>
        <div class="muted sharesub">created ${appPasswordTime(p.created_at)} · ${used}</div>
      </span>
      <button class="btn sm danger" data-act="revokeapppassword"
              data-id="${esc(p.id)}" data-label="${esc(p.label)}">Revoke</button>
    </div>`;
}

export async function showAppPasswords(){
  let list;
  try {
    list = await api('GET', '/api/app-passwords');
  } catch(e){ toast(e.message); return; }

  const rows = list.length
    ? list.map(appPasswordRow).join('')
    : '<p class="muted">No app passwords yet. Make one for each e-reader or reading app you use.</p>';

  openPage(
    'App passwords',
    'A separate password for each e-reader, so your account password never has to be typed into one.',
    `<div class="ov-empty" style="margin-bottom:14px">
       <p class="sharehead">Setting up an e-reader</p>
       <p class="muted" style="margin:0 0 6px">In KOReader, Kobo (with an OPDS
         add-on), Thorium, Moon+ Reader and the like, add an OPDS catalogue with:</p>
       <table style="font-size:.88rem; border-collapse:collapse">
         <tr><td class="muted" style="padding:2px 12px 2px 0">Address</td>
             <td style="padding:2px 0"><span class="shareurl">${esc(appPasswordOpdsUrl())}</span></td></tr>
         <tr><td class="muted" style="padding:2px 12px 2px 0">Username</td>
             <td style="padding:2px 0"><span class="shareurl">${esc(S.email || 'your email address')}</span></td></tr>
         <tr><td class="muted" style="padding:2px 12px 2px 0">Password</td>
             <td style="padding:2px 0">an app password from this page</td></tr>
       </table>
       <p class="muted" style="margin:6px 0 0; font-size:.82rem">An app password
         can browse the catalogue and download books you can see — nothing else.
         It cannot open this console, change anything, or make another app
         password. Revoke it and that device is shut out on its next request.</p>
     </div>
     <div class="row" style="justify-content:flex-end; margin-bottom:8px">
       <button class="btn primary" data-act="newapppassword">New app password…</button>
     </div>
     ${rows}`,
  );
}

export async function newAppPassword(){
  const answer = await ask({
    title: 'New app password',
    body: 'Name it after the device it is for, so you know which one to revoke later.',
    fields: [{ label: 'Device', placeholder: 'Kobo Clara, KOReader on the tablet…' }],
    confirmLabel: 'Create',
  });
  if (!answer) return;
  const label = answer[0];
  if (!label) { toast('Give it a name, so you can tell which device it is.'); return; }

  let made;
  try {
    made = await api('POST', '/api/app-passwords', { label });
  } catch(e){ toast(e.message); return; }

  // Closing this by any route refreshes the list behind it, so the new entry
  // is there once the secret is gone from the screen.
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)appPasswordShown()">
    <div class="modal" style="width:min(520px,95vw)">
      <h2 style="margin:0 0 4px">App password for “${esc(made.label)}”</h2>
      <p class="muted" style="margin:0 0 12px">Type this into the device as the
        password, with ${esc(S.email || 'your email address')} as the username.
        <strong>This is the only time it is shown</strong> — Vellum keeps only a
        hash, so if you lose it, revoke it and make another.</p>
      <div class="linkout" style="font-size:1.1rem; letter-spacing:.04em">${esc(made.password)}</div>
      <p class="muted" style="margin:8px 0 0; font-size:.82rem">Capitals, spaces
        and the dashes don't matter; type it however your keyboard makes easiest.</p>
      <div class="row">
        <button class="btn" data-act="copysecret" data-secret="${esc(made.password)}">Copy</button>
        <button class="btn primary" onclick="appPasswordShown()">Done</button>
      </div>
    </div></div>`;
}

/// The secret's dialog is closed: drop it from the page and show the list.
export function appPasswordShown(){
  closeModal();
  showAppPasswords();
}

export function copySecret(secret){
  navigator.clipboard.writeText(secret).then(() => toast('Copied'));
}

export async function revokeAppPassword(id, label){
  if (!await ask({
    title: `Revoke “${label}”?`,
    body: 'That device stops reaching your library on its next request. Anything ' +
          'it already downloaded stays on it.',
    confirmLabel: 'Revoke',
    danger: true,
  })) return;
  try {
    await api('DELETE', '/api/app-passwords/' + encodeURIComponent(id));
  } catch(e){ toast(e.message); return; }
  toast('Revoked');
  showAppPasswords();
}
