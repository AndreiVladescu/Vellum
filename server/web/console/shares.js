// Shares and public links: everything this library has let out.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { openPage } from './pages.js';

// ---- shares: everything this library has let out --------------------------
//
// One screen for both kinds, because "who can see my books" is one question:
// account shares (a person with a login) and public links (a URL). Links are
// listed whatever state they are in — live, expired, used up, revoked — since
// the useful question is usually "what did I share, and is it still open?",
// which a list of only-live links cannot answer.
//
// Account shares have no past tense to show: revoking one deletes the row, so
// what you see is what is current. The note in the screen says so rather than
// letting an empty section imply nobody was ever shared with.

export function linkState(l){
  if (l.revoked) return { label:'Revoked', cls:'off' };
  if (l.expires_at && new Date(l.expires_at.replace(' ','T') + 'Z') <= new Date())
    return { label:'Expired', cls:'off' };
  if (l.max_uses !== null && l.use_count >= l.max_uses)
    return { label:'Used up', cls:'off' };
  return { label:'Live', cls:'on' };
}

export function shareRow(s){
  const target = s.scope_label || s.scope;
  return `
    <div class="row shareline">
      <span>
        <strong>${esc(s.grantee_email)}</strong>
        <span class="muted"> · ${esc(s.permission)}</span>
        <div class="muted sharesub">${esc(target)} · shared by ${esc(s.owner_email)}
          · ${esc((s.created_at||'').slice(0,10))}</div>
      </span>
      <button class="btn sm danger" data-act="revokeshare" data-id="${esc(s.id)}">Revoke</button>
    </div>`;
}

export function linkRow(l){
  const st = linkState(l);
  const uses = l.max_uses === null ? `${l.use_count} download${l.use_count===1?'':'s'}`
                                   : `${l.use_count} of ${l.max_uses} used`;
  const bits = [
    l.kind === 'layout' ? 'room' : 'book',
    esc((l.created_at||'').slice(0,10)),
    uses,
    l.expires_at ? 'expires ' + esc(l.expires_at.slice(0,10)) : 'no expiry',
  ];
  // The URL, on the links that still work. Kept out of the closed ones on
  // purpose: a revoked link's address is a thing that no longer opens, and
  // showing it invites sending it to someone.
  const url = st.label === 'Live' && l.url
    ? `<div class="shareurl" title="${esc(l.url)}">${esc(l.url)}</div>`
    : (st.label === 'Live'
        ? '<div class="muted sharesub">Made before Vellum kept link addresses — ' +
          'revoke it and make a new one to see the URL here.</div>'
        : '');
  return `
    <div class="row shareline">
      <span>
        <strong>${esc(l.book_title)}</strong>
        ${l.has_password ? '<span class="pill">password</span>' : ''}
        <span class="pill ${st.cls}">${st.label}</span>
        <div class="muted sharesub">${bits.join(' · ')}</div>
        ${url}
      </span>
      ${st.label === 'Live'
        ? `<span class="row" style="gap:6px">
             ${l.url ? `<button class="btn sm" data-act="copyurl" data-url="${esc(l.url)}">Copy link</button>` : ''}
             <button class="btn sm danger" data-act="revokelink" data-id="${esc(l.id)}">Revoke</button>
           </span>`
        : '<span class="muted sharesub">closed</span>'}
    </div>`;
}

export async function showShares(){
  let shares = [], links = [];
  try {
    [shares, links] = await Promise.all([
      api('GET','/api/shares'),
      api('GET','/api/share-links'),
    ]);
  } catch(e){ toast(e.message); return; }

  // Who there is to share with, and what there is to share. Best-effort: the
  // people list is the master's to read, so a non-master gets the same form
  // with no suggestions rather than no form.
  let people = [];
  try { people = await api('GET','/api/users'); } catch(e){ people = []; }

  const live = links.filter(l => linkState(l).label === 'Live').length;
  const linkList = links.length
    ? links.map(linkRow).join('')
    : '<p class="muted">No public links have been made.</p>';
  const shareList = shares.length
    ? shares.map(shareRow).join('')
    : '<p class="muted">Nobody with an account has been given access.</p>';

  // The grant form. Access has always been per-book, per-tag or whole-library
  // in the API; the console could only ever *revoke*, so the only way to give
  // someone write access was an invitation, which is all-or-nothing.
  const selected = S.selected.size;
  const grant = `
    <p class="sharehead">Give someone access</p>
    <p class="muted sharesub" style="margin:0 0 8px">Read lets them see and
      sync; read &amp; write also lets them edit and upload. Revoking is on the
      list below.</p>
    <div class="row" style="gap:8px; flex-wrap:wrap; align-items:flex-end">
      <span style="display:flex; flex-direction:column">
        <label for="g-email">Person</label>
        <input id="g-email" type="email" list="g-people" placeholder="their email"
               style="min-width:220px">
        <datalist id="g-people">
          ${people.map(u => `<option value="${esc(u.email)}"></option>`).join('')}
        </datalist>
      </span>
      <span style="display:flex; flex-direction:column">
        <label for="g-scope">What</label>
        <select id="g-scope" style="width:100%">
          <option value="all">The whole library</option>
          ${selected ? `<option value="selected">The ${selected} book${selected===1?'':'s'} you ticked</option>` : ''}
          ${S.groups.map(g => `<option value="group:${esc(g.id)}">Tag: ${esc(g.name)}</option>`).join('')}
        </select>
      </span>
      <span style="display:flex; flex-direction:column">
        <label for="g-perm">Access</label>
        <select id="g-perm" style="width:100%">
          <option value="viewer">Read</option>
          <option value="editor">Read &amp; write</option>
        </select>
      </span>
      <button class="btn primary" data-act="grantaccess">Grant</button>
    </div>`;

  openPage(
    'Shares',
    `Everything this library has let out: ${live} live link${live===1?'':'s'} ` +
    `of ${links.length}, and ${shares.length} account share${shares.length===1?'':'s'}.`,
    grant +
    `<p class="sharehead" style="margin-top:22px">Public links</p>
     <p class="muted sharesub" style="margin:0 0 8px">Anyone holding the URL,
       no account needed. Kept after they close so you can see what was shared.</p>
     ${linkList}
     <p class="sharehead" style="margin-top:22px">People with accounts</p>
     <p class="muted sharesub" style="margin:0 0 8px">Current only — revoking
       one removes the record with it.</p>
     ${shareList}`,
  );
}

/// Grants what the form on the Shares page describes.
///
/// A tick-list of books becomes one share each — the API's `book` scope is a
/// single id, and looping here keeps that honest rather than inventing a bulk
/// endpoint whose failure mode ("four of nine worked") the server would then
/// have to describe.
export async function grantAccess(){
  const email = document.getElementById('g-email').value.trim();
  if (!email){ toast('Who should get access?'); return; }
  const what = document.getElementById('g-scope').value;
  const permission = document.getElementById('g-perm').value;

  const targets = what === 'selected'
    ? [...S.selected].map(id => ({ scope:'book', scope_id:id }))
    : what.startsWith('group:')
      ? [{ scope:'group', scope_id: what.slice(6) }]
      : [{ scope:'all' }];

  let done = 0;
  const failures = [];
  for (const t of targets){
    try {
      await api('POST','/api/shares', { grantee_email: email, permission, ...t });
      done++;
    } catch(e){ failures.push(e.message); }
  }
  // Partial success is reported as partial, not as success: with a tick-list
  // of books, "granted" when two of nine failed is the sort of thing nobody
  // notices until someone cannot open a book.
  if (failures.length){
    toast(done
      ? `Granted ${done} of ${targets.length} — ${failures[0]}`
      : failures[0]);
  } else {
    toast(targets.length > 1 ? `Granted on ${done} books` : 'Access granted');
  }
  showShares();
}

export async function revokeLink(id){
  if (!await ask({
    title: 'Revoke this link?',
    body: 'Anyone holding the URL loses access at once.',
    confirmLabel: 'Revoke',
    danger: true,
  })) return;
  try { await api('DELETE','/api/share-links/' + encodeURIComponent(id)); }
  catch(e){ toast(e.message); return; }
  toast('Link revoked');
  showShares();
}

export async function revokeShare(id){
  if (!await ask({
    title: 'Revoke this share?',
    body: 'They lose access to what it covered. Books they added stay.',
    confirmLabel: 'Revoke',
    danger: true,
  })) return;
  try { await api('DELETE','/api/shares/' + encodeURIComponent(id)); }
  catch(e){ toast(e.message); return; }
  toast('Share revoked');
  showShares();
}
