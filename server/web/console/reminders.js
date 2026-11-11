// Due-date reminder settings.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { openPage } from './pages.js';

/// Due-date reminders: whether they go out, when, and what they say
/// (migration 0037).
///
/// The whole screen is disabled when this server has no mailer — a switch that
/// turns on and does nothing is worse than one you cannot reach, and the
/// sentence at the top says which environment variables to set.
export async function showReminders(){
  let s;
  try { s = await api('GET','/api/settings'); }
  catch(e){ toast(e.message); return; }

  const off = !s.mail_configured;
  const field = (id, label, value, rows) => `
    <label class="stack" style="margin-bottom:12px">
      <span class="muted">${esc(label)}</span>
      ${rows
        ? `<textarea id="${id}" rows="${rows}" ${off ? 'disabled' : ''}>${esc(value)}</textarea>`
        : `<input id="${id}" type="text" value="${esc(value)}" ${off ? 'disabled' : ''}>`}
    </label>`;

  openPage(
    'Due-date reminders',
    'One email a few days before a book is due, one on the day, and one when '
      + 'it goes late — each sent once. A loan can opt out on its own in the app.',
    (off
      ? '<p class="err">This server cannot send mail, so nothing will go out. '
        + 'Set VELLUM_SMTP_HOST and VELLUM_MAIL_FROM to change that.</p>'
      : '')
    + `
    <label class="row" style="gap:8px; margin-bottom:12px">
      <input id="rm-on" type="checkbox" ${s.loan_reminders ? 'checked' : ''}
             ${off ? 'disabled' : ''}>
      <span>Send reminders for loans that have a due date and an address</span>
    </label>
    <label class="stack" style="margin-bottom:16px">
      <span class="muted">Days before the due date for the first one</span>
      <input id="rm-lead" type="number" min="0" max="90" value="${esc(String(s.lead_days))}"
             ${off ? 'disabled' : ''} style="max-width:120px">
    </label>
    <p class="muted">The messages. <code>{title}</code>, <code>{borrower}</code>,
      <code>{due_date}</code>, <code>{loaned_date}</code>, <code>{days}</code>
      and <code>{library}</code> are filled in.</p>
    <h3>Before it is due</h3>
    ${field('rm-bs', 'Subject', s.before_subject)}
    ${field('rm-bb', 'Message', s.before_body, 5)}
    <h3>On the day</h3>
    ${field('rm-ds', 'Subject', s.due_subject)}
    ${field('rm-db', 'Message', s.due_body, 5)}
    <h3>Once it is late</h3>
    ${field('rm-os', 'Subject', s.overdue_subject)}
    ${field('rm-ob', 'Message', s.overdue_body, 5)}
    <div class="row" style="gap:8px; margin-top:8px">
      <button class="btn primary" data-act="savereminders" ${off ? 'disabled' : ''}>Save</button>
      <button class="btn" data-act="runreminders" ${off ? 'disabled' : ''}>Send any due now</button>
    </div>`,
  );
}

export async function saveReminders(){
  const value = id => document.getElementById(id).value;
  try {
    await api('PUT','/api/settings',{
      loan_reminders: document.getElementById('rm-on').checked,
      lead_days: Number(value('rm-lead')),
      before_subject: value('rm-bs'), before_body: value('rm-bb'),
      due_subject: value('rm-ds'), due_body: value('rm-db'),
      overdue_subject: value('rm-os'), overdue_body: value('rm-ob'),
    });
    toast('Saved');
  } catch(e){ toast(e.message); }
}

export async function runReminders(){
  try {
    const r = await api('POST','/api/settings/loan-reminders/run');
    toast(r.sent ? `Sent ${r.sent} reminder${r.sent === 1 ? '' : 's'}`
                 : 'Nothing was due');
  } catch(e){ toast(e.message); }
}
