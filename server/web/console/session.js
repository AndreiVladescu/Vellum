// Signing in, signing out, and showing the console once signed in.

import { S } from './state.js';
import { api } from './api.js';
import { loadAll } from './books.js';
import { renderViews } from './views.js';
import { revealContentSearch } from './search.js';

export async function login(){
  const email = document.getElementById('l-email').value.trim();
  const pass = document.getElementById('l-pass').value;
  const err = document.getElementById('l-err');
  err.textContent = '';
  try {
    const r = await api('POST','/api/auth/login',{ email, password: pass });
    S.token = r.token; S.email = r.user.email;
    sessionStorage.setItem('vellum_token', S.token);
    sessionStorage.setItem('vellum_email', S.email);
    showApp();
  } catch(e){ err.textContent = e.message; }
}

export function logout(){
  S.token=null; sessionStorage.removeItem('vellum_token'); sessionStorage.removeItem('vellum_email');
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
}
