// The overview: what someone running a shared library wants to see on opening
// the console.

import { S } from './state.js';
import { esc } from './dom.js';
import { api, settle } from './api.js';
import { openPage } from './pages.js';
import { fmtBytes } from './stats.js';
import { stamp } from './loans.js';

// ---- overview ------------------------------------------------------------
//
// Built only from endpoints the console already calls, each fetched on its own.
// A member is refused some of them (the server's numbers, the activity log) and
// an older server may not have others; that must cost the page one section, not
// the whole page — so every answer is kept as `{ ok, data }` or `{ ok: false,
// status }`, and `hiddenResult()` is the one place that decides a section is
// simply not for this account. No polling: it loads when opened, and the
// Refresh button asks again.

/// How many days ahead a loan counts as "due soon".
export const SOON_DAYS = 7;

/// A 403 or 404 means "not for you" (or "this server is older"), which hides a
/// section. Anything else — a network error, a 500 — is shown as a failure, so
/// a broken server is not mistaken for an empty one.
export function hiddenResult(r){
  return !r.ok && (r.status === 403 || r.status === 404);
}

/// Whole days from one 'YYYY-MM-DD' to another. UTC midnights, so a daylight
/// saving change cannot make a day 23 hours long.
export function daysBetween(from, to){
  const t = s => Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10));
  return Math.round((t(to) - t(from)) / 86400000);
}

/// Splits the loans overview into what needs attention. A loan due today is not
/// late until tomorrow, and compares by date, not by time of day, because a due
/// date is picked as a date. Overdue comes longest-late first, soon comes
/// soonest first; a loan with no agreed date is never either.
export function classifyLoans(rows, today, soonDays = SOON_DAYS){
  const out = rows.filter(r => r.loan_id);
  const dated = out.filter(r => r.due_at).map(r => ({
    row: r,
    late: daysBetween(r.due_at.slice(0, 10), today),   // > 0 means days overdue
  }));
  const overdue = dated.filter(d => d.late > 0)
    .sort((a, b) => b.late - a.late || a.row.book_title.localeCompare(b.row.book_title));
  const soon = dated.filter(d => d.late <= 0 && -d.late <= soonDays)
    .sort((a, b) => b.late - a.late || a.row.book_title.localeCompare(b.row.book_title));
  return {
    copies: rows.length,
    out: out.length,
    overdue: overdue.map(d => ({ ...d.row, daysLate: d.late })),
    soon: soon.map(d => ({ ...d.row, daysLeft: -d.late })),
  };
}

/// "3 days late", "due today", "in 2 days" — what the date means, not the date.
export function dueWords(n){
  if (n > 0) return n === 1 ? '1 day late' : n + ' days late';
  if (n === 0) return 'due today';
  return n === -1 ? 'due tomorrow' : 'due in ' + (-n) + ' days';
}

/// Everything the page draws, as plain data: no DOM, no fetching, so it can be
/// tested by handing it canned answers. `r` holds the settled results by name.
export function buildOverview(r, today, isMaster){
  const m = { counts: [], lending: null, requests: null, notes: null, activity: null };

  // Counts. Books come from the library's own paging (what *this* account can
  // see); the rest is the server's numbers, which only the owner is given.
  if (r.books.ok) m.counts.push({ label: 'Books', value: String(r.books.data.total ?? 0), href: '#/library/books' });
  if (r.stats.ok){
    m.counts.push({ label: 'Files', value: String(r.stats.data.files) });
    m.counts.push({ label: 'People', value: String(r.stats.data.users), href: '#/people/users' });
    m.counts.push({
      label: 'Storage',
      value: fmtBytes((r.stats.data.blob_bytes || 0) + (r.stats.data.database_bytes || 0)),
      href: '#/server/about',
    });
  }
  m.emptyLibrary = r.books.ok && (r.books.data.total ?? 0) === 0;
  m.booksFailed = !r.books.ok && !hiddenResult(r.books);

  if (!hiddenResult(r.loans)){
    m.lending = r.loans.ok
      ? { ok: true, ...classifyLoans(r.loans.data, today) }
      : { ok: false, message: r.loans.message };
  }
  if (!hiddenResult(r.requests)){
    m.requests = r.requests.ok
      ? { ok: true, pending: r.requests.data.filter(x => x.status === 'pending') }
      : { ok: false, message: r.requests.message };
  }
  if (!hiddenResult(r.notes)){
    m.notes = r.notes.ok
      ? { ok: true, unread: r.notes.data.unread || 0, items: r.notes.data.notifications || [] }
      : { ok: false, message: r.notes.message };
  }
  // The activity log is the owner's, and an account that is known to be a
  // member is not even asked; an unknown role is, and the server decides.
  if (isMaster !== false && !hiddenResult(r.audit)){
    m.activity = r.audit.ok
      ? { ok: true, enabled: !!r.audit.data.enabled, rows: r.audit.data.rows || [] }
      : { ok: false, message: r.audit.message };
  }
  return m;
}

const ROW = 'justify-content:space-between; gap:12px; padding:6px 0; border-bottom:1px solid var(--line)';

function section(title, link, inner){
  return `<section class="ov-section">
    <div class="row" style="justify-content:space-between; gap:12px; align-items:baseline">
      <h3>${esc(title)}</h3>${link || ''}
    </div>${inner}</section>`;
}

function more(href, label){
  return `<a class="btn sm quiet" href="${esc(href)}">${esc(label)}</a>`;
}

function failed(message){
  return `<p class="muted">Could not load this: ${esc(message || 'unknown error')}</p>`;
}

function loanLines(list, words){
  return list.map(l => `
    <div class="row" style="${ROW}">
      <span><strong>${esc(l.book_title)}</strong>
        <span class="muted">· with ${esc(l.borrower)}</span></span>
      <span class="muted" style="white-space:nowrap">${esc(words(l))}
        · ${esc(l.due_at.slice(0, 10))}</span>
    </div>`).join('');
}

/// The page body. Escapes every server-provided string.
export function overviewHtml(m){
  const parts = [];

  if (m.counts.length){
    parts.push(`<div class="ov-tiles">${m.counts.map(c => {
      const inner = `<span class="ov-num">${esc(c.value)}</span>
        <span class="muted">${esc(c.label)}</span>`;
      return c.href
        ? `<a class="ov-tile" href="${esc(c.href)}">${inner}</a>`
        : `<div class="ov-tile">${inner}</div>`;
    }).join('')}</div>`);
  }
  if (m.booksFailed) parts.push(failed('the book count did not load'));
  if (m.emptyLibrary){
    parts.push(`<p class="ov-empty">The library is empty. Start with a single book,
      or bring in a list you already have.
      <span class="row" style="gap:6px; margin-top:8px">
        <button class="btn sm primary" data-act="addbook">Add book</button>
        <button class="btn sm" data-act="navaction" data-id="import">Import books…</button>
      </span></p>`);
  }

  if (m.lending){
    const L = m.lending;
    let inner;
    if (!L.ok) inner = failed(L.message);
    else if (!L.copies){
      inner = `<p class="muted">No physical copies are recorded yet. Add one to a
        book in the app, and it can be lent from here.</p>`;
    } else {
      const late = L.overdue.length
        ? `<p class="ov-sub late">Overdue</p>${loanLines(L.overdue, l => dueWords(l.daysLate))}` : '';
      const soon = L.soon.length
        ? `<p class="ov-sub">Due in the next ${SOON_DAYS} days</p>${loanLines(L.soon, l => dueWords(-l.daysLeft))}` : '';
      inner = (late || soon)
        ? late + soon
        : '<p class="muted">Nothing is overdue or due this week.</p>';
      inner += `<p class="muted" style="margin:8px 0 0">${L.out} of ${L.copies}
        ${L.copies === 1 ? 'copy is' : 'copies are'} out.</p>`;
    }
    parts.push(section('Loans', more('#/lending/loans', 'All loans'), inner));
  }

  if (m.requests){
    const Q = m.requests;
    let inner;
    if (!Q.ok) inner = failed(Q.message);
    else if (!Q.pending.length) inner = '<p class="muted">Nobody is waiting on you.</p>';
    else {
      inner = Q.pending.slice(0, 5).map(x => `
        <div class="row" style="${ROW}">
          <span><strong>${esc(x.book_title)}</strong>
            <span class="muted">· ${esc(x.requester_email)}</span></span>
          <span class="muted" style="white-space:nowrap">${esc((x.created_at || '').slice(0, 10))}</span>
        </div>`).join('');
      if (Q.pending.length > 5){
        inner += `<p class="muted" style="margin:8px 0 0">and ${Q.pending.length - 5} more.</p>`;
      }
    }
    const title = Q.ok && Q.pending.length
      ? `Borrow requests (${Q.pending.length} waiting)` : 'Borrow requests';
    parts.push(section(title, more('#/lending/requests',
      Q.ok && Q.pending.length ? 'Answer them' : 'Requests page'), inner));
  }

  if (m.notes){
    const N = m.notes;
    let inner;
    if (!N.ok) inner = failed(N.message);
    else if (!N.unread) inner = '<p class="muted">Nothing new.</p>';
    else {
      inner = N.items.filter(n => !n.read_at).slice(0, 5).map(n => `
        <div class="row" style="${ROW}">
          <span>${esc(n.title)}</span>
          <span class="muted" style="white-space:nowrap">${esc((n.created_at || '').slice(0, 10))}</span>
        </div>`).join('');
    }
    parts.push(section(N.ok && N.unread ? `Notifications (${N.unread} unread)` : 'Notifications', '', inner));
  }

  if (m.activity){
    const A = m.activity;
    let inner;
    if (!A.ok) inner = failed(A.message);
    else if (!A.enabled){
      inner = `<p class="muted">The activity log is off on this server. Set
        <code>VELLUM_AUDIT=1</code> and restart to record who changed what.</p>`;
    } else if (!A.rows.length) inner = '<p class="muted">Nothing recorded yet.</p>';
    else {
      inner = A.rows.map(a => `
        <div class="row" style="${ROW}">
          <span><strong>${esc(a.action)}</strong>${a.detail ? ' · ' + esc(a.detail) : ''}</span>
          <span class="muted" style="font-size:12px; white-space:nowrap">
            ${esc(a.actor_email || 'unknown')} · ${esc((a.at || '').replace('T', ' ').slice(0, 16))}</span>
        </div>`).join('');
    }
    parts.push(section('Recent activity', A.ok && A.enabled ? more('#/server/activity', 'Full log') : '', inner));
  }

  return parts.join('') + `<div class="row" style="margin-top:18px">
      <button class="btn sm" data-act="refreshoverview">Refresh</button></div>`;
}

export async function showOverview(){
  const [books, stats, loans, requests, notes, audit] = await Promise.all([
    settle(api('GET', '/api/books?page=1&limit=1')),
    // Skipped for an account known to be a member: the answer can only be 403.
    S.isMaster === false ? { ok: false, status: 403 } : settle(api('GET', '/api/admin/stats')),
    settle(api('GET', '/api/loans/overview')),
    settle(api('GET', '/api/borrow-requests?direction=incoming')),
    settle(api('GET', '/api/notifications?unread=1&limit=5')),
    S.isMaster === false ? { ok: false, status: 403 } : settle(api('GET', '/api/admin/audit?limit=8')),
  ]);
  const model = buildOverview({ books, stats, loans, requests, notes, audit },
    stamp(new Date()).slice(0, 10), S.isMaster);
  openPage('Overview', 'Where the library stands today.', overviewHtml(model));
}
