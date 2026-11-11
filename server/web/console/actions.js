// The delegated click/dblclick/change tables behind every `data-act` attribute.

import { S } from './state.js';
import { sortBy, toggleMissing, toggleTagFilter } from './books.js';
import { startEdit, titleClick, titleDbl, toggleRow } from './table.js';
import { applyView, deleteView, toggleCol } from './views.js';
import { importToggle } from './import.js';
import { pickUpload } from './uploads.js';
import { quickAdd, removeTag } from './tags.js';
import { cancelDetail, deleteBook, detailPick, enrichFromDetail,
  pickDetailCandidate, saveDetail } from './detail.js';
import { copyUrl, createLink, openLink, openReader } from './links.js';
import { decideRequest } from './requests.js';
import { deleteCopyFromConsole, lendCopyFromConsole, returnCopyFromConsole,
  showBookCopies } from './loans.js';
import { runReminders, saveReminders } from './reminders.js';
import { shareRoom } from './rooms.js';
import { grantAccess, revokeLink, revokeShare } from './shares.js';
import { invitePerson, removePerson, renamePerson, resetFor, revokeInvite,
  setRole } from './people.js';
import { showMailSetup, testMail } from './mail.js';
import { showActivity } from './activity.js';

// ---- delegated events ---------------------------------------------------
//
// **Why nothing here uses `onclick="fn('${value}')"`.** That is a JS string
// inside an HTML attribute, and an HTML parser decodes character references in
// attribute values *before* the JS engine is handed the source. So `esc()` —
// which turns `'` into `&#39;` — is undone on the way in, and a room named
//
//     My room'+alert(document.domain)+'
//
// executes when the master opens the rooms list. Any member can publish a room,
// so that was stored XSS from a low-privileged account into the admin console
// (security audit, S5).
//
// Escaping for a nested context correctly is possible and is a trap: it has to
// be right every time, at thirty call sites, forever. Data attributes are plain
// text — escaped once as HTML, read back through `dataset`, never parsed as
// code — so the nesting simply does not exist.
export const ACTIONS = {
  tagfilter: el => toggleTagFilter(el.dataset.id),
  missing: el => toggleMissing(el.dataset.key),
  sort: el => sortBy(el.dataset.col),
  removetag: el => removeTag(el.dataset.group, el.dataset.book),
  titleclick: el => titleClick(el.dataset.book),
  quickadd: el => quickAdd(el, el.dataset.book),
  openreader: el => openReader(el.dataset.book),
  pickupload: el => pickUpload(el.dataset.book),
  openlink: el => openLink(el.dataset.book),
  detailpick: el => detailPick(el.dataset.book, el.dataset.accept),
  deletebook: el => deleteBook(el.dataset.book),
  enrichdetail: el => enrichFromDetail(el.dataset.book),
  savedetail: el => saveDetail(el.dataset.book),
  canceldetail: () => cancelDetail(),
  pickdetail: el => pickDetailCandidate(Number(el.dataset.i)),
  createlink: el => createLink(el.dataset.book),
  copyurl: el => copyUrl(el.dataset.url),
  decide: el => decideRequest(el.dataset.id, el.dataset.decision),
  lendcopy: el => lendCopyFromConsole(el.dataset.copy),
  returncopy: el => returnCopyFromConsole(el.dataset.loan, el.dataset.copy,
    el.dataset.borrower, el.dataset.since),
  savereminders: () => saveReminders(),
  runreminders: () => runReminders(),
  // The room viewer has no sign-in form of its own — unlike reopening the
  // console itself in a new tab, there is nothing there to "just sign in
  // again" on. sessionStorage isn't shared with a tab window.open() creates,
  // so the token rides in the URL fragment instead (never sent to the
  // server, unlike a query string) and the new tab picks it up once. See the
  // matching comment in room.js.
  viewroom: el => window.open(
    '/room/' + encodeURIComponent(el.dataset.id) + '#t=' + encodeURIComponent(S.token),
    '_blank', 'noopener',
  ),
  shareroom: el => shareRoom(el.dataset.id, el.dataset.name),
  activity: el => showActivity(el.dataset.before === '' ? null : Number(el.dataset.before)),
  setrole: el => setRole(el.dataset.id, el.dataset.master === '1'),
  renameperson: el => renamePerson(el.dataset.id, el.dataset.name),
  showcopies: el => showBookCopies(el.dataset.book),
  deletecopy: el => deleteCopyFromConsole(el.dataset.copy, el.dataset.book),
  resetfor: el => resetFor(el.dataset.email),
  removeperson: el => removePerson(el.dataset.id, el.dataset.email),
  revokeinvite: el => revokeInvite(el.dataset.id),
  invite: () => invitePerson(),
  mailtest: () => testMail(),
  mailhelp: () => showMailSetup(),
  revokelink: el => revokeLink(el.dataset.id),
  revokeshare: el => revokeShare(el.dataset.id),
  grantaccess: () => grantAccess(),
  applyview: el => applyView(el.dataset.name),
  deleteview: el => deleteView(el.dataset.name),
};

export const DBL_ACTIONS = {
  titleedit: (el, ev) => titleDbl(ev, el.dataset.book),
  startedit: (el, ev) => startEdit(ev, el.dataset.book, el.dataset.field),
};

export const CHANGE_ACTIONS = {
  togglerow: el => toggleRow(el.dataset.book, el.checked),
  importtoggle: el => importToggle(Number(el.dataset.index), el.checked),
  togglecol: el => toggleCol(el.dataset.key, el.checked),
};

export function delegate(type, table, attr) {
  document.addEventListener(type, ev => {
    const el = ev.target.closest('[' + attr + ']');
    if (!el) return;
    const fn = table[el.getAttribute(attr)];
    if (fn) fn(el, ev);
  });
}
