// Dialogs: `ask()` (the styled confirm/prompt) and closing a modal.

import { esc } from './dom.js';

/// A styled stand-in for `confirm()` and `prompt()`.
///
/// The browser's own dialogs were doing real work here — revoking a share,
/// deleting books, naming a tag, taking a due date — and every one of them
/// looked like a security warning from 1998: no styling, the site's hostname
/// at the top, and a title bar that says nothing about what you are agreeing
/// to. They also block the whole tab, which is why a slow one feels like a
/// hang.
///
/// Returns a promise: `null` if it was dismissed, otherwise an object of the
/// field values (`{}` for a plain confirmation). So a caller reads as
///
///     if (!await ask({ title: '…' })) return;
///
/// and a prompt-shaped one destructures what it asked for.
export let _askResolve = null;

/// Which fields of the open dialog hold a secret, by index. A secret is read
/// back exactly as typed: trimming a password changes it, so one with a leading
/// or trailing space could never be confirmed. A field is secret if it is
/// `type: 'password'` or says `secret: true` (for a secret shown in the clear).
let _askSecret = new Set();

/// `html` is author-written markup, `body` is text that gets escaped. Two
/// parameters rather than one because everything passed here so far has been a
/// sentence containing somebody's email address, and the day one of those is
/// interpolated into markup is the day a display name becomes a script tag.
/// `cancelLabel: null` drops the button, for a dialog that only says something.
export function ask({ title, body = '', html = '', fields = [], confirmLabel = 'OK',
               cancelLabel = 'Cancel', danger = false, width = 460 }){
  return new Promise(resolve => {
    _askResolve = resolve;
    _askSecret = new Set(fields.flatMap((f, i) => (f.secret || f.type === 'password') ? [i] : []));
    const inputs = fields.map((f, i) => `
      <label for="ask-${i}">${esc(f.label)}</label>
      ${f.options
        ? `<select id="ask-${i}" style="width:100%">${
            f.options.map(o => `<option value="${esc(o.value)}"${
              o.value === f.value ? ' selected' : ''}>${esc(o.label)}</option>`).join('')
          }</select>`
        : `<input id="ask-${i}" type="${esc(f.type || 'text')}"
                  value="${esc(f.value || '')}"
                  placeholder="${esc(f.placeholder || '')}" style="width:100%">`}
      ${f.hint ? `<p class="muted" style="font-size:12px; margin:4px 0 10px">${esc(f.hint)}</p>` : ''}
    `).join('');

    document.getElementById('modal-root').innerHTML = `
     <div class="modal-bg" onclick="if(event.target===this)askDone(false)">
      <div class="modal" style="width:min(${width}px,95vw)"
           onkeydown="if(event.key==='Escape')askDone(false);
                      else if(event.key==='Enter'&&event.target.tagName!=='TEXTAREA')askDone(true)">
        <h2 style="margin:0 0 8px">${esc(title)}</h2>
        ${body ? `<p class="muted" style="margin:0 0 12px">${esc(body)}</p>` : ''}
        ${html ? `<div class="muted" style="margin:0 0 12px">${html}</div>` : ''}
        ${inputs}
        <div class="row" style="justify-content:flex-end; gap:8px; margin-top:14px">
          ${cancelLabel
            ? `<button class="btn" onclick="askDone(false)">${esc(cancelLabel)}</button>`
            : ''}
          <button class="btn ${danger ? 'danger' : 'primary'}"
                  onclick="askDone(true)">${esc(confirmLabel)}</button>
        </div>
      </div></div>`;

    const first = document.getElementById('ask-0');
    if (first) { first.focus(); if (first.select) first.select(); }
  });
}

/// Closes the dialog opened by [ask] and settles its promise.
export function askDone(ok){
  const resolve = _askResolve;
  _askResolve = null;
  const values = {};
  for (let i = 0; ; i++){
    const el = document.getElementById('ask-' + i);
    if (!el) break;
    const typed = el.value || '';
    values[i] = _askSecret.has(i) ? typed : typed.trim();
  }
  _askSecret = new Set();
  closeModal();
  if (resolve) resolve(ok ? values : null);
}

export function closeModal(){ document.getElementById('modal-root').innerHTML=''; }
