// The API client: authenticated fetches, blob URLs for covers, file downloads.

import { S } from './state.js';
import { toast } from './dom.js';
import { logout } from './session.js';

export async function api(method, path, body){
  const res = await fetch(path, {
    method,
    headers: { 'content-type':'application/json', ...(S.token?{authorization:'Bearer '+S.token}:{}) },
    body: body!==undefined ? JSON.stringify(body) : undefined,
  });
  // A 401 used to log you out on the spot. That is right when the session is
  // gone and wrong for anything else that answers 401 — and being thrown back
  // to the login screen destroys whatever you were in the middle of, which was
  // reported after inviting someone. So ask whether the session is actually
  // dead before acting as though it is.
  if (res.status === 401) {
    if (await sessionIsDead()) {
      logout();
      throw new Error('Session expired — please sign in again.');
    }
    const data = await res.json().catch(()=>null);
    throw new Error((data && data.error) || 'That request was not authorised.');
  }
  const data = res.status===204 ? null : await res.json().catch(()=>null);
  if (!res.ok) {
    // The status rides along so a page that can live without an endpoint (the
    // overview) can tell "not for you" (403/404) from "broke".
    const err = new Error((data&&data.error) || ('HTTP '+res.status));
    err.status = res.status;
    throw err;
  }
  return data;
}

/// A request's outcome kept rather than thrown, for a page made of several
/// independent requests where one refusal must not cost the others.
export async function settle(promise){
  try { return { ok: true, data: await promise }; }
  catch(e){ return { ok: false, status: e.status || 0, message: e.message }; }
}

/// Whether the stored token is genuinely no longer accepted.
///
/// Asked only after something *else* answered 401, and deliberately with the
/// cheapest authenticated endpoint there is. If this succeeds the session is
/// fine and the 401 belonged to that one request, which is worth a message
/// rather than an eviction. A network failure here counts as alive: being
/// signed out because the wifi dropped is the very thing this prevents.
export async function sessionIsDead(){
  if (!S.token) return true;
  try {
    const res = await fetch('/api/auth/me',
      { headers: { authorization: 'Bearer ' + S.token } });
    return res.status === 401;
  } catch(e){
    return false;
  }
}

// Fetch an authenticated blob and hand back an object URL. The session token
// rides the Authorization header (never the URL), so it can't leak into proxy
// logs or history; the caller is responsible for revoking the URL.
export async function authBlobUrl(path){
  const res = await fetch(path, { headers: S.token?{authorization:'Bearer '+S.token}:{} });
  if (res.status === 401) {
    if (await sessionIsDead()) { logout(); throw new Error('Session expired'); }
    throw new Error('That request was not authorised.');
  }
  if (!res.ok) throw new Error('HTTP '+res.status);
  return URL.createObjectURL(await res.blob());
}

// Load every `<img data-src>` under `root` with an auth-header fetch, swapping
// in an object URL once fetched (and revoking it after the image decodes). On
// failure we invoke the element's own onerror, so the no-cover placeholder
// still appears exactly as it did with a direct `src`.
export function hydrateImages(root){
  for (const img of root.querySelectorAll('img[data-src]')){
    const path = img.getAttribute('data-src');
    img.removeAttribute('data-src');
    authBlobUrl(path).then(url=>{
      img.addEventListener('load', ()=>URL.revokeObjectURL(url), { once:true });
      img.src = url;
    }).catch(()=>{ if (typeof img.onerror === 'function') img.onerror(); });
  }
}

// Download an authenticated file by fetching it with the auth header and
// triggering a save from the resulting object URL, so the token stays out of
// the `<a href>`.
export async function downloadFile(fileId, filename){
  try {
    const url = await authBlobUrl('/api/files/'+fileId);
    const a = document.createElement('a');
    a.href = url; a.download = filename || 'download';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(()=>URL.revokeObjectURL(url), 10000);
  } catch(e){ toast('Download failed'); }
}
