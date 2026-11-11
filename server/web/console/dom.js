// Small helpers every module uses: escaping, toasts, and reading a book row.

import { S } from './state.js';

export function esc(s){ return (s??'').toString().replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
export function toast(m){ const t=document.createElement('div'); t.className='toast'; t.textContent=m;
  document.body.appendChild(t); setTimeout(()=>t.remove(),2200); }
export function key(g,b){ return g+'|'+b; }
export function authorStr(b){ return (b.authors||[]).join(', '); }
export function bookTags(b){ return S.groups.filter(g=>S.members.has(key(g.id,b.id))); }
