// Signing in, signing out, and showing the console once signed in.

import { rememberRole, S } from './state.js';
import { toast } from './dom.js';
import { loadAll } from './books.js';
import { renderViews } from './views.js';
import { revealContentSearch } from './search.js';
import { startRouter } from './router.js';

/// The challenge a right password on a two-factor account was answered with,
/// while the code is being asked for. Kept in memory only, never storage: it
/// is worth five minutes and one sign-in.
export const LOGIN = { challenge: null };

/// A sign-in request, outside `api()` on purpose: there is no session yet, so
/// a 401 here is an answer ("wrong password", "now the code") and never a
/// session that expired.
export async function authPost(path, body){
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(()=>null);
  if (res.ok || (res.status === 401 && data && data.two_factor_required)) return data;
  throw new Error((data && data.error) || ('HTTP ' + res.status));
}

export async function login(){
  const email = document.getElementById('l-email').value.trim();
  const pass = document.getElementById('l-pass').value;
  const err = document.getElementById('l-err');
  err.textContent = '';
  try {
    const r = await authPost('/api/auth/login', { email, password: pass });
    if (r.two_factor_required) { askLoginCode(r.challenge); return; }
    signedIn(r);
  } catch(e){ err.textContent = e.message; }
}

/// Swap the password form for the code form.
export function askLoginCode(challenge){
  LOGIN.challenge = challenge;
  document.getElementById('l-pass').value = '';
  document.getElementById('l-form').classList.add('hidden');
  document.getElementById('l-2fa').classList.remove('hidden');
  const code = document.getElementById('l-code');
  code.value = '';
  code.focus();
}

export function cancelLoginCode(){
  LOGIN.challenge = null;
  document.getElementById('l-2fa').classList.add('hidden');
  document.getElementById('l-form').classList.remove('hidden');
}

export async function loginCode(){
  const err = document.getElementById('l-err');
  err.textContent = '';
  const code = document.getElementById('l-code').value.trim();
  if (!code) { err.textContent = 'Type the code from your authenticator app.'; return; }
  try {
    const r = await authPost('/api/auth/login/2fa', { challenge: LOGIN.challenge, code });
    cancelLoginCode();
    signedIn(r);
    if (typeof r.recovery_codes_left === 'number') {
      toast(`Recovery code used — ${r.recovery_codes_left} left. ` +
            'Make new ones under People and sharing → Account security.');
    }
  } catch(e){
    err.textContent = e.message;
    // The server gave up on this challenge (too many wrong codes, or it
    // expired): back to the password, which is the only way forward.
    if (/start again/.test(e.message)) cancelLoginCode();
  }
}

function signedIn(r){
  S.token = r.token; S.email = r.user.email;
  sessionStorage.setItem('vellum_token', S.token);
  sessionStorage.setItem('vellum_email', S.email);
  rememberRole(r.user);
  showApp();
}

export function logout(){
  S.token=null; sessionStorage.removeItem('vellum_token'); sessionStorage.removeItem('vellum_email');
  rememberRole(null);
  document.getElementById('app').classList.add('hidden');
  document.getElementById('login').classList.remove('hidden');
}

export function showApp(){
  document.getElementById('login').classList.add('hidden');
  document.getElementById('app').classList.remove('hidden');
  document.getElementById('who').textContent = S.email || '';
  document.getElementById('tbl').classList.toggle('compact', S.compact);
  revealContentSearch();
  renderViews();
  loadAll();
  startRouter();
}
