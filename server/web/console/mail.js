// Mail: the status strip, the test send, and the setup help.

import { esc, toast } from './dom.js';
import { api } from './api.js';
import { ask } from './dialogs.js';

/// Whether this server can send mail, on the screen where it matters.
///
/// The People screen is where the absence is felt: with no relay every
/// invitation has to be copied out of a dialog and pasted into a chat window,
/// and nothing on screen said why, or that it could be otherwise.
export function mailStrip(mail){
  const box = 'margin:18px 0 0; padding:10px 12px; border:1px solid var(--line);'
    + ' border-radius:8px; font-size:12px';
  if (mail && mail.enabled) {
    return `
      <div class="row" style="${box}; justify-content:space-between; gap:12px">
        <span class="muted">Email is on — invitations and password resets are
          sent from <strong>${esc(mail.from || 'this server')}</strong>.</span>
        <button class="btn sm" data-act="mailtest">Send me a test</button>
      </div>`;
  }
  return `
    <div class="row" style="${box}; justify-content:space-between; gap:12px">
      <span class="muted">Email is off — invitations appear here as a link for
        you to pass along yourself.</span>
      <button class="btn sm" data-act="mailhelp">Set up email</button>
    </div>`;
}

/// Sends a test to the signed-in owner's own address.
///
/// The relay's own refusal is shown rather than a tidy summary: "535 Username
/// and Password not accepted" tells you which of the five variables is wrong,
/// and "could not send" tells you nothing.
export async function testMail(){
  toast('Sending…');
  try {
    const res = await api('POST','/api/mail/test');
    toast('Sent to ' + (res.sent_to || 'your address') + ' — check that it arrives.');
  } catch(e){ toast(e.message); }
}

/// What to set, and where — the five variables, in one place.
export function showMailSetup(){
  ask({
    title: 'Setting up email',
    width: 560,
    html: `<p style="margin:0 0 4px">Vellum sends nothing until you give it a relay. These go in the
      server's environment — the <code>[Service]</code> section of its systemd
      unit, your <code>docker-compose.yml</code>, or the shell that starts it —
      and take effect on restart.</p>
      <table style="width:100%; margin:12px 0; font-size:12px; border-collapse:collapse">
        <tr><td style="padding:3px 8px 3px 0"><code>VELLUM_SMTP_HOST</code></td>
            <td class="muted">The relay. Setting it is what turns mail on.</td></tr>
        <tr><td style="padding:3px 8px 3px 0"><code>VELLUM_SMTP_PORT</code></td>
            <td class="muted">Defaults to 587, which is usually right.</td></tr>
        <tr><td style="padding:3px 8px 3px 0"><code>VELLUM_SMTP_USER</code></td>
            <td class="muted">Your account with the relay.</td></tr>
        <tr><td style="padding:3px 8px 3px 0"><code>VELLUM_SMTP_PASS</code></td>
            <td class="muted">Its password.</td></tr>
        <tr><td style="padding:3px 8px 3px 0"><code>VELLUM_MAIL_FROM</code></td>
            <td class="muted">The sender people will see. Required.</td></tr>
      </table>
      <p style="margin:0">For Gmail: host <code>smtp.gmail.com</code>, and an <strong>app
      password</strong> rather than your own — which needs 2-step verification
      switched on first. Get one wrong and the server refuses to start and says
      which, so a bad setup never reaches the people you invite. Once it is
      running, come back here and send yourself a test.</p>`,
    confirmLabel: 'Got it',
    cancelLabel: null,
  });
}
