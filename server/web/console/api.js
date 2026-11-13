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

// Short-lived signed links (POST /api/links) for covers and downloads: a URL
// good for one resource and a few hours or minutes, so a plain `<img src>` or
// `<a href>` works and the browser can cache covers, with the session token
// still out of every URL. Cached per path until a minute before expiry.
const linkCache = new Map();

/// Signed URLs for `paths` (no query strings), as a Map path -> url. A path the
/// caller cannot view, or any failure, is simply absent: callers fall back to
/// the header-authenticated blob fetch.
export async function signedLinks(paths){
  const now = Date.now() / 1000, out = new Map(), need = [];
  for (const p of new Set(paths)){
    const hit = linkCache.get(p);
    if (hit && hit.expires_at - 60 > now) out.set(p, hit.url); else need.push(p);
  }
  if (need.length && S.token){
    try {
      const res = await fetch('/api/links', { method:'POST',
        headers: { authorization:'Bearer '+S.token, 'content-type':'application/json' },
        body: JSON.stringify({ paths: need }) });
      if (res.ok) for (const l of (await res.json()).links || []){
        linkCache.set(l.path, l);
        out.set(l.path, l.url);
      }
    } catch(e){ /* fall back to blob fetches */ }
  }
  return out;
}

// Load every `<img data-src>` under `root`. One request signs all the covers;
// each image then uses its signed URL directly (a query such as `?w=` or `?t=`
// is re-attached after the signature, which covers the path only). Anything
// that could not be signed falls back to an auth-header fetch into an object
// URL. On failure the element's own onerror runs, so the no-cover placeholder
// still appears exactly as it did with a direct `src`.
export function hydrateImages(root){
  const imgs = [];
  for (const img of root.querySelectorAll('img[data-src]')){
    imgs.push([img, img.getAttribute('data-src')]);
    img.removeAttribute('data-src');
  }
  if (!imgs.length) return;
  signedLinks(imgs.map(([, src]) => src.split('?')[0])).then(links => {
    for (const [img, src] of imgs){
      const [path, query] = src.split('?');
      const signed = links.get(path);
      if (signed){
        img.src = signed + (query ? '&'+query : '');
        continue;
      }
      authBlobUrl(src).then(url=>{
        img.addEventListener('load', ()=>URL.revokeObjectURL(url), { once:true });
        img.src = url;
      }).catch(()=>{ if (typeof img.onerror === 'function') img.onerror(); });
    }
  });
}

// Download a book file through a short-lived (five minute) signed link, or, if
// none can be had, by fetching it with the auth header into an object URL.
export async function downloadFile(fileId, filename){
  const path = '/api/files/'+fileId;
  const url = (await signedLinks([path])).get(path);
  if (url){
    const a = document.createElement('a');
    a.href = url; a.download = filename || 'download';
    document.body.appendChild(a); a.click(); a.remove();
    return true;
  }
  return downloadPath(path, filename);
}

/// The same for any authenticated GET — a book file, or the server's backup.
/// The whole response is held in memory as a blob before the save starts, which
/// is fine for a book and worth knowing for a backup of a very large library.
export async function downloadPath(path, filename){
  try {
    const url = await authBlobUrl(path);
    const a = document.createElement('a');
    a.href = url; a.download = filename || 'download';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(()=>URL.revokeObjectURL(url), 10000);
    return true;
  } catch(e){ toast('Download failed'); return false; }
}
