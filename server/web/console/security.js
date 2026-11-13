// Account security: two-factor sign-in for the signed-in account (v1.6.2).
//
// Every account has this page, like app passwords: each person turns their
// own second factor on and off. The server decides everything that matters —
// this page only asks, shows and confirms:
//
// - Setting up asks for the password first (a session left open must not be
//   able to enrol a phone of its own), then shows the QR code and the key, and
//   turns it on only once a code from the app is confirmed.
// - Recovery codes are shown once, in the dialog that made them; the page
//   afterwards says how many are left, never which.
// - Turning it off, or making new recovery codes, asks for the password or a
//   current code.
//
// The QR code arrives from the server as an SVG and is shown through a `data:`
// URL in an <img>, so nothing from the response is ever parsed as markup.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask, closeModal } from './dialogs.js';
import { openPage } from './pages.js';
import { showPeople } from './people.js';

/// `2026-11-13 09:41:07` (UTC, as SQLite stores it) → `2026-11-13`.
function securityDate(s){ return esc((s || '').slice(0, 10)); }

export async function showSecurity(){
  let st;
  try {
    st = await api('GET', '/api/auth/2fa');
  } catch(e){
    if (e.status === 404) {
      openPage('Account security', '',
        '<p class="muted">This server is too old for two-factor sign-in. Upgrade it to turn it on.</p>');
      return;
    }
    toast(e.message); return;
  }

  const body = st.enabled ? `
     <p class="sharehead">Two-factor sign-in is <strong>on</strong></p>
     <p class="muted" style="margin:0 0 10px">Since ${securityDate(st.enabled_at)}.
       Signing in to this console or the Vellum app asks for a code from your
       authenticator app after your password.</p>
     <p style="margin:0 0 14px" class="${st.recovery_codes_left <= 3 ? 'err' : 'muted'}">
       ${st.recovery_codes_left} of 10 recovery codes left${st.recovery_codes_left <= 3
         ? ' — make new ones before you run out' : ''}.</p>
     <div class="row" style="gap:8px">
       <button class="btn" data-act="regen2fa">New recovery codes…</button>
       <button class="btn danger" data-act="disable2fa">Turn off…</button>
     </div>`
    : `
     <p class="sharehead">Two-factor sign-in is off</p>
     <p class="muted" style="margin:0 0 14px">Turn it on and signing in also asks
       for a six-digit code from an authenticator app on your phone (Aegis, 2FAS,
       Google Authenticator, 1Password…), so a password that leaks is not enough
       on its own.</p>
     <button class="btn primary" data-act="setup2fa">Set up two-factor…</button>`;

  openPage(
    'Account security',
    'How your account signs in.',
    `${body}
     <div class="ov-empty" style="margin-top:18px">
       <p class="muted" style="margin:0; font-size:.82rem">E-readers sign in with
         <strong>app passwords</strong>, which do not ask for a code — a device
         cannot type one. With two-factor on, your account password no longer
         works on an e-reader at all, so give each one an app password.
         Sessions already signed in stay signed in.</p>
     </div>`,
  );
}

/// Turn it on: password, then the QR code and a code from it, then the
/// recovery codes.
export async function setup2fa(){
  const proof = await ask({
    title: 'Set up two-factor sign-in',
    body: 'First, confirm it is you.',
    fields: [{ label: 'Password', type: 'password' }],
    confirmLabel: 'Continue',
  });
  if (!proof) return;
  if (!proof[0]) { toast('Type your password to continue.'); return; }

  let s;
  try {
    s = await api('POST', '/api/auth/2fa/setup', { password: proof[0] });
  } catch(e){ toast(e.message); return; }

  // Asked until a code works or the dialog is dismissed: a typo, or a phone
  // whose clock is off, should not mean scanning a new code.
  let problem = '';
  for (;;) {
    const answer = await ask({
      title: 'Scan this with your authenticator app',
      html: `
        <div style="text-align:center">
          <img alt="QR code for your authenticator app" width="200" height="200"
               style="background:#fff; padding:6px; border-radius:6px"
               src="data:image/svg+xml;base64,${btoa(s.qr_svg)}">
        </div>
        <p style="margin:8px 0 4px">Or add it by hand with this key:</p>
        <div class="linkout" style="letter-spacing:.06em">${esc(s.secret)}</div>
        <p style="margin:10px 0 0">Then type the six-digit code the app shows.</p>
        ${problem ? `<p class="err" style="margin:8px 0 0">${esc(problem)}</p>` : ''}`,
      fields: [{ label: 'Code', placeholder: '123 456' }],
      confirmLabel: 'Turn on',
      width: 420,
    });
    if (!answer) return;
    try {
      const r = await api('POST', '/api/auth/2fa/enable', { code: answer[0] });
      showRecoveryCodes(r.recovery_codes, true);
      return;
    } catch(e){ problem = e.message; }
  }
}

/// The recovery codes, once. Closing it by any route redraws the page behind.
export function showRecoveryCodes(codes, justEnabled){
  const all = codes.join('\n');
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)recoveryCodesShown()">
    <div class="modal" style="width:min(460px,95vw)">
      <h2 style="margin:0 0 4px">${justEnabled ? 'Two-factor sign-in is on' : 'New recovery codes'}</h2>
      <p class="muted" style="margin:0 0 12px">Each of these signs you in once
        instead of a code, for the day your phone is lost. Keep them somewhere
        that is not your phone. <strong>This is the only time they are
        shown</strong>${justEnabled ? '' : ' — the old ones no longer work'}.</p>
      <div class="linkout" style="font-family:monospace; columns:2; line-height:1.7">${
        codes.map(c => `<div>${esc(c)}</div>`).join('')}</div>
      <div class="row">
        <button class="btn" data-act="copysecret" data-secret="${esc(all)}">Copy</button>
        <button class="btn primary" onclick="recoveryCodesShown()">Done</button>
      </div>
    </div></div>`;
}

export function recoveryCodesShown(){
  closeModal();
  showSecurity();
}

/// The one field both "turn off" and "new recovery codes" ask for. A six-digit
/// number or something shaped like a recovery code is sent as a code; anything
/// else as the password.
export function securityProof(typed){
  const compact = typed.replace(/[\s-]/g, '');
  return /^\d{6}$/.test(compact) || /^[0-9a-z]{16}$/i.test(compact)
    ? { code: typed }
    : { password: typed };
}

async function askProof(title, confirmLabel, danger){
  const answer = await ask({
    title,
    body: 'Confirm it is you with your password, or a code from your authenticator app.',
    fields: [{ label: 'Password or code', type: 'password' }],
    confirmLabel,
    danger,
  });
  if (!answer) return null;
  if (!answer[0]) { toast('Type your password or a code.'); return null; }
  return securityProof(answer[0]);
}

export async function disable2fa(){
  const proof = await askProof('Turn off two-factor sign-in?', 'Turn off', true);
  if (!proof) return;
  try {
    await api('POST', '/api/auth/2fa/disable', proof);
  } catch(e){ toast(e.message); return; }
  toast('Two-factor sign-in is off');
  showSecurity();
}

export async function regen2fa(){
  const proof = await askProof('Make new recovery codes?', 'Make new codes', false);
  if (!proof) return;
  let r;
  try {
    r = await api('POST', '/api/auth/2fa/recovery-codes', proof);
  } catch(e){ toast(e.message); return; }
  showRecoveryCodes(r.recovery_codes, false);
}

/// An owner clearing someone else's, from People — for a lost phone.
export async function clear2fa(id, email){
  if (!await ask({
    title: `Clear two-factor sign-in for ${email}?`,
    body: 'They will sign in with just their password until they set it up again. ' +
          'Do this only for someone you know has lost their phone and recovery codes.',
    confirmLabel: 'Clear it',
    danger: true,
  })) return;
  try {
    await api('DELETE', '/api/users/' + encodeURIComponent(id) + '/2fa');
  } catch(e){ toast(e.message); return; }
  toast('Cleared');
  showPeople();
}
