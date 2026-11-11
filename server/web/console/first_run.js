// First run: creating the master account on a server with no accounts.

import { rememberRole, S } from './state.js';
import { api } from './api.js';
import { showApp } from './session.js';

// ---- first run: creating the master account ------------------------------
//
// A brand-new server has nobody to log in as, and the console used to show a
// login box regardless — a dead end unless you knew the app or curl could
// register for you. `GET /api/auth/registration` says whether that first
// account can still be made; the form appears only in that window, because
// once a master exists the endpoint permanently answers "closed".

export async function checkRegistration(){
  try {
    const r = await api('GET','/api/auth/registration');
    if (!r || !r.open) return;
    document.getElementById('r-token').classList.toggle('hidden', !r.bootstrap_token_required);
    showRegister();
  } catch(e){
    // An older server has no such route. Leaving the login form up is exactly
    // the old behaviour, so a 404 here is not worth saying anything about.
  }
}

export function showRegister(){
  document.getElementById('login').classList.add('hidden');
  document.getElementById('register').classList.remove('hidden');
  document.getElementById('r-email').focus();
}

export function showLogin(){
  document.getElementById('register').classList.add('hidden');
  document.getElementById('login').classList.remove('hidden');
  document.getElementById('l-to-register').classList.remove('hidden');
}

export async function register(){
  const email = document.getElementById('r-email').value.trim();
  const name = document.getElementById('r-name').value.trim();
  const pass = document.getElementById('r-pass').value;
  const tokenField = document.getElementById('r-token');
  const err = document.getElementById('r-err');
  err.textContent = '';
  try {
    const body = { email, display_name: name, password: pass };
    if (!tokenField.classList.contains('hidden')) {
      body.bootstrap_token = tokenField.value.trim();
    }
    const r = await api('POST','/api/auth/register', body);
    // Registering signs you in — the server hands back a session token, so
    // making the account and then being shown a login form would be silly.
    S.token = r.token; S.email = r.user.email;
    sessionStorage.setItem('vellum_token', S.token);
    sessionStorage.setItem('vellum_email', S.email);
    rememberRole(r.user);
    document.getElementById('register').classList.add('hidden');
    showApp();
  } catch(e){ err.textContent = e.message; }
}
