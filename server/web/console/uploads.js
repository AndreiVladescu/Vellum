// Uploading files and covers, the progress bar, and bulk metadata fetch.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { loadAll } from './books.js';

// ---- uploads (unchanged) ------------------------------------------------

export async function classify(file){
  const buf = new Uint8Array(await file.slice(0,16).arrayBuffer());
  const m = sig => sig.every((byte,i)=>buf[i]===byte);
  if (m([0x25,0x50,0x44,0x46])) return 'pdf';
  if (m([0xFF,0xD8,0xFF]) || m([0x89,0x50,0x4E,0x47]) || m([0x47,0x49,0x46,0x38])) return 'image';
  if (m([0x50,0x4B,0x03,0x04]) && file.name.toLowerCase().endsWith('.epub')) return 'epub';
  return 'unsupported';
}

// `onCancel`, when given, adds a Stop button — a long bulk operation the user
// cannot stop is a long bulk operation they learn not to start.
export function showProgress(label, onCancel){
  let el = document.getElementById('uprog');
  if (!el){
    el = document.createElement('div');
    el.id = 'uprog'; el.className = 'uprog';
    el.innerHTML = '<div class="uprog-label"></div><div class="uprog-track"><div class="uprog-bar"></div></div><div class="uprog-pct"></div><button class="btn sm uprog-cancel hidden">Stop</button>';
    document.body.appendChild(el);
  }
  el.querySelector('.uprog-label').textContent = label;
  el.querySelector('.uprog-bar').style.width = '0%';
  el.querySelector('.uprog-pct').textContent = '0%';
  const cancel = el.querySelector('.uprog-cancel');
  cancel.classList.toggle('hidden', !onCancel);
  cancel.onclick = onCancel || null;
  el.style.display = 'flex';
}
// `detail` names what is being worked on right now, so a stalled bulk run shows
// *which* book it stalled on.
export function setProgress(fraction, detail){
  const el = document.getElementById('uprog'); if (!el) return;
  const pct = Math.round(fraction * 100);
  el.querySelector('.uprog-bar').style.width = pct + '%';
  el.querySelector('.uprog-pct').textContent = (pct >= 100 ? 'finishing…' : pct + '%');
  if (detail !== undefined){
    const label = el.querySelector('.uprog-label');
    label.textContent = label.textContent.split(' — ')[0] + (detail ? ' — ' + detail : '');
  }
}
export function hideProgress(){ const el = document.getElementById('uprog'); if (el) el.style.display = 'none'; }

export function xhrUpload(method, url, file, mime){
  return new Promise((resolve, reject)=>{
    const xhr = new XMLHttpRequest();
    xhr.open(method, url);
    xhr.setRequestHeader('authorization', 'Bearer ' + S.token);
    xhr.setRequestHeader('content-type', mime);
    xhr.upload.onprogress = e => { if (e.lengthComputable) setProgress(e.loaded / e.total); };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) return resolve();
      let msg = 'Upload failed (HTTP ' + xhr.status + ')';
      try { const j = JSON.parse(xhr.responseText); if (j.error) msg = j.error; } catch(_) {}
      reject(new Error(msg));
    };
    xhr.onerror = () => reject(new Error('Network error during upload'));
    xhr.send(file);
  });
}

export async function uploadTo(id, file){
  const kind = await classify(file);
  if (kind !== 'image' && kind !== 'pdf' && kind !== 'epub'){
    toast('Only PDF, EPUB, or image files are accepted');
    return false;
  }
  showProgress('Uploading ' + file.name);
  try {
    if (kind === 'image'){
      await xhrUpload('PUT', '/api/books/'+id+'/cover', file, file.type || 'image/jpeg');
      toast('Cover updated'); await loadAll();
    } else {
      const mime = kind === 'epub' ? 'application/epub+zip' : 'application/pdf';
      await xhrUpload('POST', '/api/books/'+id+'/files?filename='+encodeURIComponent(file.name), file, mime);
      toast('Uploaded ' + file.name);
      await enrichBook(id);          // fill missing author/year/etc. from the title
      await loadAll();
    }
    return true;
  } catch(e){ toast(e.message); return false; }
  finally { hideProgress(); }
}

// Ask the server to fill a book's empty fields from an online metadata lookup.
// Best-effort: a miss or a network error leaves the book untouched.
export async function enrichBook(id){
  try { await api('POST','/api/books/'+id+'/enrich'); }
  catch(_){ /* non-fatal — the upload/create still succeeded */ }
}

// Cancellable, with per-item results (plan 5 #35). Fetching metadata for 500
// books used to be a spinner and hope: no way to know which ones failed, and no
// way to stop. The cancel flag is checked between books rather than mid-request,
// so a cancel never leaves a half-applied update.
export let bulkCancelled = false;
export function cancelBulk(){ bulkCancelled = true; toast('Stopping after this book…'); }

export async function enrichSelected(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  const ids = [...S.selected];
  const byId = new Map(S.books.map(b=>[b.id, b.title]));
  bulkCancelled = false;
  showProgress('Fetching metadata…', cancelBulk);

  const failed = [];
  let done = 0, ok = 0;
  for (const id of ids){
    if (bulkCancelled) break;
    setProgress(done/ids.length, byId.get(id) || '');
    try { await api('POST','/api/books/'+id+'/enrich'); ok++; }
    catch(e){ failed.push({ title: byId.get(id) || id, error: e.message }); }
    done++;
  }
  hideProgress();
  await loadAll();

  if (!failed.length){
    toast(bulkCancelled
      ? `Stopped after ${done} of ${ids.length} — ${ok} updated`
      : `Fetched metadata for ${ok} book(s)`);
    return;
  }
  // Per-item results, because "3 failed" without naming them is unactionable.
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Fetched ${ok} of ${done}</h2>
      <p class="muted" style="margin:0 0 12px">These could not be looked up —
        usually no ISBN, or nothing matched.</p>
      <div style="max-height:50vh; overflow:auto">${
        failed.map(f=>`<div class="row" style="justify-content:space-between; gap:12px;
          padding:6px 0; border-bottom:1px solid var(--line)">
          <span>${esc(f.title)}</span>
          <span class="muted" style="font-size:12px">${esc(f.error)}</span></div>`).join('')
      }</div>
      <div class="row" style="justify-content:flex-end; margin-top:12px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

export function pickUpload(id){
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub,image/*';
  input.onchange = ()=>{ if (input.files[0]) uploadTo(id, input.files[0]); };
  input.click();
}

// Apply one picked file to every selected book (a shared cover, say).
export async function uploadToSelected(){
  if (!S.selected.size){ toast('Select some books first'); return; }
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.pdf,.epub,image/*';
  input.onchange = async ()=>{
    const f = input.files[0]; if (!f) return;
    const kind = await classify(f);
    if (kind!=='image' && kind!=='pdf' && kind!=='epub'){ toast('Only PDF, EPUB, or image files'); return; }
    const ids = [...S.selected];
    const what = kind==='image' ? 'cover' : 'file';
    if (!await ask({
      title: `Apply this ${what} to ${ids.length} book${ids.length===1?'':'s'}?`,
      body: `${f.name} — the ones you have ticked.`,
      confirmLabel: 'Apply',
    })) return;
    let ok=0;
    for (const id of ids){
      showProgress('Uploading to '+ok+'/'+ids.length);
      try {
        if (kind==='image') await xhrUpload('PUT','/api/books/'+id+'/cover', f, f.type||'image/jpeg');
        else { const mime=kind==='epub'?'application/epub+zip':'application/pdf';
               await xhrUpload('POST','/api/books/'+id+'/files?filename='+encodeURIComponent(f.name), f, mime); }
        ok++;
      } catch(e){ toast(e.message); }
    }
    hideProgress(); await loadAll(); toast('Applied to '+ok+' book(s)');
  };
  input.click();
}

export function dragOver(e, tr){ e.preventDefault(); tr.classList.add('drop'); }
export function dragLeave(tr){ tr.classList.remove('drop'); }
export function dropOn(e, id, tr){
  e.preventDefault(); tr.classList.remove('drop');
  const f = e.dataTransfer.files[0];
  if (f) uploadTo(id, f);
}
