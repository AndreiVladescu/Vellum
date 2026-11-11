// People: accounts and invitations.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { openPage } from './pages.js';
import { mailStrip } from './mail.js';

// ---- people (plan 6 #1) ---------------------------------------------------
//
// Administering the accounts in a shared library. Master-only, and the only
// place it exists: creating a second user used to mean hand-crafting an
// authenticated HTTP request, which made every sharing feature unreachable in
// practice.
//
// Inviting is preferred over creating with a password. An invite lets the
// person choose their own, and never puts a password the admin knows into the
// database — the same reasoning as the reset flow.

export async function showPeople(){
  let users, invites;
  try {
    users = await api('GET','/api/users');
  } catch(e){
    toast(/master/.test(e.message)
      ? 'Only the library owner can manage people.'
      : e.message);
    return;
  }
  // Invites need SMTP to be *sent*, but the list works regardless — a server
  // without mail still mints links to pass along by hand.
  try { invites = await api('GET','/api/invites'); } catch(e){ invites = []; }
  // An older server has no such endpoint; treat that the same as off, since
  // either way there is nothing here to configure from this screen.
  let mail;
  try { mail = await api('GET','/api/mail/status'); } catch(e){ mail = { enabled: false }; }

  const rows = users.map(u => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span>
        <strong>${esc(u.display_name || u.email)}</strong>
        ${u.is_master ? '<span class="muted"> · owner</span>' : ''}
        <div class="muted" style="font-size:12px; margin-top:3px">${esc(u.email)}</div>
      </span>
      <span class="row" style="gap:6px">
        <button class="btn sm" data-act="renameperson" data-id="${esc(u.id)}"
                data-name="${esc(u.display_name)}">Rename</button>
        <button class="btn sm" data-act="setrole" data-id="${esc(u.id)}" data-master="${u.is_master ? '0' : '1'}">
          ${u.is_master ? 'Make member' : 'Make owner'}</button>
        <button class="btn sm" data-act="resetfor" data-email="${esc(u.email)}">Send reset</button>
        <button class="btn sm danger" data-act="removeperson" data-id="${esc(u.id)}" data-email="${esc(u.email)}">
          Remove</button>
      </span>
    </div>`).join('');

  const pending = invites.length ? `
    <p class="muted" style="margin:14px 0 4px">Invited, not yet joined</p>` +
    invites.map(i => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:6px 0; font-size:13px">
      <span>
        ${i.display_name ? `<strong>${esc(i.display_name)}</strong>
          <span class="muted">· ${esc(i.email)}</span>`
          : esc(i.email)}
        <span class="muted">· ${esc(i.as_owner ? 'an owner'
          : accessLabel(i.permission))}</span>
      </span>
      <button class="btn sm" data-act="revokeinvite" data-id="${esc(i.id)}">Withdraw</button>
    </div>`).join('') : '';

  openPage(
    'People',
    'Everyone with an account on this server. An owner can manage people and '
      + 'see the whole library; a member sees only what has been shared with them.',
    `${rows}${pending}
     <p class="sharehead" style="margin-top:22px">Invite someone</p>
     <div class="row" style="gap:16px 20px; align-items:flex-end; flex-wrap:wrap">
       <span style="display:flex; flex-direction:column; flex:1 1 180px">
         <label for="inv-name">Name</label>
         <input id="inv-name" type="text" placeholder="Ana" style="width:100%"
                autocomplete="off">
       </span>
       <span style="display:flex; flex-direction:column; flex:2 1 240px">
         <label for="inv-email">Email address</label>
         <input id="inv-email" type="email" placeholder="ana@example.com"
                style="width:100%" autocomplete="off"
                onkeydown="if(event.key==='Enter')invitePerson()">
       </span>
       <span style="display:flex; flex-direction:column">
         <label for="inv-perm">Access</label>
         <select id="inv-perm" style="width:100%">
           <option value="viewer">View only</option>
           <option value="editor">Read &amp; write</option>
           <option value="owner">Owner</option>
         </select>
       </span>
       <button class="btn primary" data-act="invite">Invite</button>
     </div>
     <p class="muted" style="font-size:12px; margin:8px 0 0">
       The invitation goes to the <strong>email address</strong> — that is what
       the account is. The name is just what to call them, and they can change
       it when they join. They choose their own password, and without SMTP the
       link is shown here to pass along yourself.</p>
     <p class="muted" style="font-size:12px; margin:6px 0 0">
       <strong>View only</strong> and <strong>read &amp; write</strong> share
       your whole library with them — the difference is whether they can change
       what they find. An <strong>owner</strong> is not shared with at all:
       they see and manage everything on the server, including other people.</p>
     ${mailStrip(mail)}`,
  );
}

export async function setRole(id, isMaster){
  try {
    await api('PUT','/api/users/'+id, { is_master: isMaster });
    toast(isMaster ? 'Now an owner.' : 'Now a member.');
    showPeople();
  } catch(e){ toast(e.message); }
}

// The email address is the account — that's what signing in uses, and it
// doesn't change here. The display name is just what to call them, which is
// why an owner can fix it without their involvement: it's not a credential.
export async function renamePerson(id, currentName){
  const answer = await ask({
    title: 'Rename',
    body: "This changes what they're called, not how they sign in — their "
      + 'email address stays the same.',
    fields: [{ label: 'Display name', value: currentName, placeholder: 'Ana' }],
    confirmLabel: 'Save',
  });
  const name = answer ? answer[0] : '';
  if (!name) return;
  try {
    await api('PUT','/api/users/'+id, { display_name: name });
    toast('Renamed.');
    showPeople();
  } catch(e){ toast(e.message); }
}

// Removing an account is the one action here that destroys something, so it
// says exactly what goes: the cascade takes their highlights, sittings, notes
// and shares, and leaves the books.
export async function removePerson(id, email){
  if (!await ask({
    title: 'Remove ' + email + '?',
    body: 'Their highlights, notes, reading history and shares go with them. '
      + 'Books they added stay in the library.',
    confirmLabel: 'Remove',
    danger: true,
  })) return;
  try {
    await api('DELETE','/api/users/'+id);
    toast('Removed.');
    showPeople();
  } catch(e){ toast(e.message); }
}

export async function invitePerson(){
  const email = document.getElementById('inv-email').value.trim();
  const name = document.getElementById('inv-name').value.trim();

  // Caught here as well as on the server, because the round trip is not what
  // makes this clear — the field it names is. Typing the name somebody is
  // known by into the address box is the mistake this screen kept inviting.
  if (!email){ toast('An email address is needed to send the invitation.'); return; }
  if (!email.includes('@')){
    toast('“' + email + '” looks like a name, not an email address. '
      + 'Put it in the Name field and give their address here.');
    document.getElementById('inv-email').focus();
    return;
  }

  // Three answers to "what will they be able to do?", and the third is not a
  // permission at all: an owner has no share, they have the run of the server.
  const level = document.getElementById('inv-perm').value;
  const grant = level === 'owner'
    ? { as_owner: true }
    : { scope: 'all', permission: level };

  let res;
  try {
    res = await api('POST','/api/invites',
      { email, display_name: name || undefined, ...grant });
  } catch(e){ toast(e.message); return; }

  document.getElementById('inv-email').value = '';
  document.getElementById('inv-name').value = '';
  // `url` comes back only when the server could not email it — a LAN server
  // with no SMTP, which is the ordinary case here.
  // The link is shown whether or not it was emailed: mail landing in a spam
  // folder used to mean withdrawing the invitation and starting again.
  //
  // showPeople() is *not* called here when there is a link: it calls
  // openPage(), which starts by closing whatever modal is open — so calling
  // it right after opening the link dialog closed the dialog it had just
  // shown, the instant that call's own fetch resolved (9/2 report: "it will
  // show for a moment... but then it will disappear"). showInviteLink()
  // refreshes the list itself once its dialog is actually dismissed.
  if (res && res.url) showInviteLink(res, name, level);
  else {
    toast('Invited ' + (name || email) + ' — ' + accessLabel(level) + '.');
    showPeople();
  }
}

/// The link, when the server has no mail to send it with.
///
/// This used to be `prompt()`: a browser dialog with the URL crammed into a
/// text box, no way to tell what it was for, and "OK / Cancel" as the only
/// choices on something that cannot be cancelled — the invitation is already
/// made. It is a real dialog now, and its one job is handing over the link.
/// What an invitation will make somebody, in the words the form used.
export function accessLabel(level){
  if (level === 'owner') return 'an owner';
  if (level === 'editor') return 'read & write';
  return 'view only';
}

export function showInviteLink(res, name, level){
  const who = esc(name || res.email);
  const expires = esc((res.expires_at || '').slice(0, 10));
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this){closeModal();showPeople();}">
    <div class="modal" style="width:min(560px,95vw)">
      <h2 style="margin:0 0 4px">Invitation ready for ${who}</h2>
      <p style="margin:0 0 8px">They will join as
        <strong>${esc(accessLabel(level))}</strong>.</p>
      <p class="muted" style="margin:0 0 12px">${res.emailed
        ? `Emailed to <strong>${esc(res.email)}</strong>. Here is the same link,
           in case it does not arrive — no need to invite them twice.`
        : `This server has no email set up, so pass the link along yourself —
           a message, a chat, written on paper.`}
        It works once, expires on ${expires}, and lets them choose their own
        password.</p>
      <input id="inv-url" readonly value="${esc(res.url)}" style="width:100%"
             onclick="this.select()">
      <div class="row" style="justify-content:flex-end; gap:8px; margin-top:12px">
        <button class="btn" onclick="closeModal();showPeople()">Done</button>
        <button class="btn primary" data-act="copyurl"
                data-url="${esc(res.url)}">Copy link</button>
      </div>
    </div></div>`;
  const field = document.getElementById('inv-url');
  if (field) field.select();
}

export async function revokeInvite(id){
  try {
    await api('DELETE','/api/invites/'+encodeURIComponent(id));
    showPeople();
  } catch(e){ toast(e.message); }
}

export async function resetFor(email){
  try {
    await api('POST','/api/auth/forgot', { email });
    toast('If mail is configured, a reset link is on its way.');
  } catch(e){ toast(e.message); }
}
