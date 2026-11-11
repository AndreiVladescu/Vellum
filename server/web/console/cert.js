// The server's TLS certificate, for importing into the app.

import { esc, toast } from './dom.js';
import { api } from './api.js';

// ---- server certificate (for importing into the app) --------------------

export let _certPem = '';

// Show the server's TLS certificate so it can be imported into the Vellum app
// (Server -> Import) instead of copying cert.pem off the box by hand. 404 when
// the server runs over plain HTTP — there's nothing to import.
export async function showCert(){
  let cert;
  try { cert = await api('GET','/api/cert'); }
  catch(e){
    toast(/not using TLS/.test(e.message)
      ? 'This server runs over HTTP — there is no certificate to import.'
      : e.message);
    return;
  }
  _certPem = cert.pem;
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Server certificate</h2>
      <p class="muted" style="margin:0 0 12px">Import this into the Vellum app
        (Server → Import) to connect over HTTPS. Check the fingerprint matches the
        one the server logged on startup before trusting it.</p>
      <label>SHA-256 fingerprint</label>
      <div style="font-family:monospace; font-size:12px; word-break:break-all;
                  padding:8px 10px; border:1px solid var(--line); border-radius:8px;
                  background:var(--row); margin-bottom:10px">${esc(cert.fingerprint)}</div>
      <label>Certificate (PEM)</label>
      <textarea readonly rows="8" onclick="this.select()"
                style="width:100%; font-family:monospace; font-size:12px">${esc(cert.pem)}</textarea>
      <div class="row" style="justify-content:flex-end; gap:8px; margin-top:12px">
        <button class="btn" onclick="copyCert()">Copy PEM</button>
        <button class="btn" onclick="downloadCert()">Download cert.pem</button>
        <button class="btn primary" onclick="closeModal()">Close</button>
      </div>
    </div>
   </div>`;
}

export function copyCert(){
  if (navigator.clipboard) {
    navigator.clipboard.writeText(_certPem)
      .then(()=>toast('Certificate copied'), ()=>toast('Copy failed — select the text and copy manually'));
  } else {
    toast('Select the text and copy manually');
  }
}

export function downloadCert(){
  const blob = new Blob([_certPem], { type:'application/x-pem-file' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = 'cert.pem';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(()=>URL.revokeObjectURL(url), 10000);
}
