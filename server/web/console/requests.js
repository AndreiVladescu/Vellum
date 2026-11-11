// Borrow requests waiting on you.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { openPage } from './pages.js';
import { pick } from './menus.js';

// ---- borrow requests (plan 5 #49) ---------------------------------------

export async function showRequests(){
  let incoming, copies;
  try {
    // The copies come too, because whether a request *can* be approved depends
    // on there being a copy free. Offering "Lend it" on a book whose only copy
    // is already in someone else's hands is a button that can only fail.
    [incoming, copies] = await Promise.all([
      api('GET','/api/borrow-requests?direction=incoming'),
      api('GET','/api/loans/overview'),
    ]);
  } catch(e){ toast(e.message); return; }

  const free = new Set(copies.filter(c => !c.loan_id).map(c => c.book_id));
  const held = {};
  for (const c of copies){
    if (c.loan_id && !free.has(c.book_id)) held[c.book_id] = c.borrower;
  }

  const pending = incoming.filter(r => r.status === 'pending');
  const rows = pending.length ? pending.map(r => {
    const canLend = free.has(r.book_id);
    const why = held[r.book_id]
      ? `every copy is with ${esc(held[r.book_id])}`
      : 'no physical copy is on record';
    return `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span>
        <strong>${esc(r.book_title)}</strong>
        <span class="muted">· ${esc(r.requester_email)}</span>
        ${r.note ? `<div class="muted" style="font-size:12px">“${esc(r.note)}”</div>` : ''}
        ${canLend ? '' : `<div class="muted" style="font-size:12px">Can’t lend — ${why}.</div>`}
      </span>
      <span class="row" style="gap:6px">
        <button class="btn sm" data-act="decide" data-id="${esc(r.id)}" data-decision="declined">Decline</button>
        ${canLend
          ? `<button class="btn sm primary" data-act="decide" data-id="${esc(r.id)}" data-decision="approved">Lend it</button>`
          : ''}
      </span>
    </div>`;
  }).join('')
    : '<p class="muted">Nobody is waiting on you.</p>';

  const answered = incoming.filter(r => r.status !== 'pending');
  const history = answered.length ? `
    <p class="muted" style="margin:14px 0 4px">Answered</p>` + answered.map(r => `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:4px 0; font-size:13px">
      <span>${esc(r.book_title)} <span class="muted">· ${esc(r.requester_email)}</span></span>
      <span class="muted">${esc(r.status)}</span>
    </div>`).join('') : '';

  openPage(
    'Borrow requests',
    "Approving creates the loan — it appears under the book's copies with the "
      + 'due date you pick. A request for a book that is already out can only be '
      + 'declined; mark it returned under Loans first.',
    `${rows}${history}`,
  );
}

export async function decideRequest(id, status){
  const body = { status };
  if (status === 'approved'){
    // A date or nothing: "borrow it as long as you like" is a real
    // arrangement, and forcing a date would describe one nobody made.
    const answer = await ask({
      title: 'Lend it',
      body: 'The loan is recorded against a free copy, and they are told.',
      fields: [{
        label: 'Due back on',
        type: 'date',
        hint: 'Leave empty for no agreed date.',
      }],
      confirmLabel: 'Lend it',
    });
    if (!answer) return;
    if (answer[0]) body.due_at = answer[0] + ' 00:00:00';
  } else {
    const answer = await ask({
      title: 'Decline this request',
      body: 'They are told either way; a reason is optional.',
      fields: [{ label: 'Reason', placeholder: 'Someone else has it' }],
      confirmLabel: 'Decline',
    });
    if (!answer) return;
    if (answer[0]) body.reply = answer[0];
  }
  try {
    await api('POST','/api/borrow-requests/' + id + '/decide', body);
  } catch(e){ toast(e.message); return; }
  toast(status === 'approved' ? 'Lent — the loan is recorded' : 'Answered');
  showRequests();
}
