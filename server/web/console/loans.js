// Loans and physical copies.

import { S } from './state.js';
import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';
import { openPage } from './pages.js';

// ---- loans: who has which copy ------------------------------------------
//
// A loan is bookkeeping for a physical object, so the question this page
// answers is "where are my books?" — which is a question about *copies*,
// including the ones sitting on the shelf. Borrow requests are the other half:
// there you answer someone who asked, here you record a book you handed over
// across a kitchen table, and you take one back.

/// Server timestamps are 'YYYY-MM-DD HH:MM:SS' in UTC, and mixing formats here
/// would sort wrongly against rows the app wrote.
export function stamp(d){ return d.toISOString().slice(0, 19).replace('T', ' '); }

export function loanId(){
  // Ids are client-chosen everywhere in this API; a v4 uuid is what every other
  // client generates.
  return (crypto.randomUUID && crypto.randomUUID()) ||
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
}

export async function showLoans(){
  let rows;
  try { rows = await api('GET','/api/loans/overview'); }
  catch(e){ toast(e.message); return; }

  const out = rows.filter(r => r.loan_id);
  const body = rows.length ? rows.map(r => {
    const where = r.location ? ` <span class="muted">· ${esc(r.location)}</span>` : '';
    const status = r.loan_id
      ? `<div class="muted" style="font-size:12px">With ${esc(r.borrower)}`
        + ` since ${esc((r.loaned_at||'').slice(0,10))}`
        + (r.due_at ? ` · due ${esc(r.due_at.slice(0,10))}` : ' · no date agreed')
        + '</div>'
      : '<div class="muted" style="font-size:12px">On the shelf</div>';
    // A reader can see where a book is but cannot move it, so they get the
    // state and no buttons rather than buttons that would answer 403.
    const action = !r.can_edit ? ''
      : r.loan_id
        ? `<button class="btn sm" data-act="returncopy" data-loan="${esc(r.loan_id)}"
             data-copy="${esc(r.copy_id)}" data-borrower="${esc(r.borrower)}"
             data-since="${esc(r.loaned_at)}">Mark returned</button>`
        : `<button class="btn sm primary" data-act="lendcopy"
             data-copy="${esc(r.copy_id)}">Lend</button>`;
    return `
    <div class="row" style="justify-content:space-between; gap:12px;
        padding:8px 0; border-bottom:1px solid var(--line)">
      <span><strong>${esc(r.book_title)}</strong>${where}${status}</span>
      <span class="row" style="gap:6px">${action}</span>
    </div>`;
  }).join('')
    : '<p class="muted">No physical copies are recorded yet. Add one to a book '
      + 'in the app, and it can be lent from here.</p>';

  openPage(
    'Loans',
    rows.length
      ? `${out.length} of ${rows.length} ${rows.length === 1 ? 'copy is' : 'copies are'} out.`
        + ' A copy can only be in one person’s hands at a time.'
      : '',
    body,
  );
}

export async function lendCopyFromConsole(copyId){
  // One dialog rather than two prompts in a row: they are one decision, and
  // the second prompt gave no way back to the first.
  const answer = await ask({
    title: 'Lend this copy',
    fields: [
      { label: 'Lend to', placeholder: 'A name, or an email' },
      {
        label: 'Due back on',
        type: 'date',
        hint: 'Leave empty for no agreed date.',
      },
    ],
    confirmLabel: 'Lend it',
  });
  if (!answer) return;
  const borrower = (answer[0] || '').trim();
  if (!borrower) return;
  const body = {
    copy_id: copyId,
    borrower: borrower,
    loaned_at: stamp(new Date()),
  };
  if (answer[1]) body.due_at = answer[1] + ' 00:00:00';
  try { await api('PUT','/api/loans/' + loanId(), body); }
  catch(e){ toast(e.message); return; }
  toast('Lent to ' + borrower);
  showLoans();
}

export async function returnCopyFromConsole(id, copyId, borrower, since){
  // A return is an edit of the loan, not a delete: the history is the point.
  // The immutable fields have to be sent back unchanged or the server refuses
  // the push.
  try {
    await api('PUT','/api/loans/' + id, {
      copy_id: copyId,
      borrower: borrower,
      loaned_at: since,
      returned_at: stamp(new Date()),
    });
  } catch(e){ toast(e.message); return; }
  toast('Back on the shelf');
  showLoans();
}

/// One book's physical copies, in a modal rather than the full Loans page —
/// "how many of this do I actually own, and where" is a question about one
/// book, not the whole shelf. Two calls rather than one: `/api/copies` has
/// the location/condition/notes a copy carries, `/api/loans/overview` has
/// its lending state and `can_edit` — merged here by copy id so the row
/// shows both without the server needing a third, book-scoped endpoint.
export async function showBookCopies(bookId){
  let copies, loans;
  try {
    [copies, loans] = await Promise.all([
      api('GET','/api/copies'),
      api('GET','/api/loans/overview'),
    ]);
  } catch(e){ toast(e.message); return; }

  const loanByCopy = new Map(loans.map(l => [l.copy_id, l]));
  const mine = copies.filter(c => c.book_id === bookId);
  // The title from the loans overview when there's a lent (or ever-lent) copy
  // to read it off of; falls back to a currently-loaded row so an unlent book
  // still gets a real heading instead of "Copies of undefined".
  const title = mine.length
    ? (loanByCopy.get(mine[0].id)?.book_title
       ?? S.books.find(b => b.id === bookId)?.title ?? '')
    : (S.books.find(b => b.id === bookId)?.title ?? '');

  const list = mine.length ? mine.map(c => {
    const loan = loanByCopy.get(c.id);
    const canEdit = loan ? loan.can_edit : true;
    const status = loan && loan.loan_id
      ? `With ${esc(loan.borrower)} since ${esc((loan.loaned_at||'').slice(0,10))}`
        + (loan.due_at ? ` · due ${esc(loan.due_at.slice(0,10))}` : ' · no date agreed')
      : 'On the shelf';
    return `
    <div style="padding:10px 12px; margin-bottom:8px; border:1px solid var(--line);
        border-radius:8px">
      <div class="row" style="justify-content:space-between; gap:12px; align-items:flex-start">
        <span>
          <strong>${c.location ? esc(c.location) : '<span class="dim">Somewhere…</span>'}</strong>
          <div class="muted" style="font-size:12px">${esc(status)}</div>
          ${c.notes ? `<div class="muted" style="font-size:12px">${esc(c.notes)}</div>` : ''}
        </span>
        ${canEdit
          ? `<button class="btn sm danger" data-act="deletecopy"
               data-copy="${esc(c.id)}" data-book="${esc(bookId)}">Delete</button>`
          : ''}
      </div>
    </div>`;
  }).join('')
    : '<p class="muted">No physical copies recorded for this book.</p>';

  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal" style="width:min(480px,95vw); max-height:80vh; overflow:auto">
      <h2 style="margin:0 0 4px">Physical copies</h2>
      <p class="muted" style="margin:0 0 12px">${esc(title)} — ${mine.length}
        ${mine.length === 1 ? 'copy' : 'copies'} on record.</p>
      ${list}
      <div class="row" style="justify-content:flex-end; gap:8px; margin-top:4px">
        <button class="btn" onclick="closeModal()">Close</button>
      </div>
    </div></div>`;
}

/// Deletes one physical copy — its placement, loan history and any condition
/// photos go with it (the same cascade the app's own delete uses), so this
/// asks first and says so, more sharply when the copy is currently on loan.
export async function deleteCopyFromConsole(copyId, bookId){
  let loans;
  try { loans = await api('GET','/api/loans/overview'); }
  catch(e){ toast(e.message); return; }
  const loan = loans.find(l => l.copy_id === copyId);
  const onLoan = !!(loan && loan.loan_id);

  const ok = await ask({
    title: 'Delete this copy?',
    body: onLoan
      ? "It's currently on loan — deleting it removes that loan, its "
        + "history and any condition photos too. This can't be undone."
      : 'Its loan history and any condition photos go with it. '
        + "This can't be undone.",
    confirmLabel: 'Delete',
    danger: true,
  });
  if (!ok) return;
  try { await api('DELETE', '/api/copies/' + encodeURIComponent(copyId)); }
  catch(e){ toast(e.message); return; }
  toast('Copy deleted.');
  showBookCopies(bookId);
}
