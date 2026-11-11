// Pages: the full-width views that replace the books table.

import { esc } from './dom.js';
import { closeModal } from './dialogs.js';
import { render, renderSelectionBar } from './table.js';

// ---- pages (as opposed to boxes on top) ----------------------------------
//
// Shares, borrow requests, people, rooms and the activity log are *lists you
// read*, not questions you answer, and a modal is the wrong container for one:
// it is small, it floats over the thing you were doing, and it cannot be
// scrolled or linked to comfortably. They open as pages now, in the same place
// the library table sits and with the same shape — a heading, a line saying
// what you are looking at, and rows.
//
// Modals are kept for what they are good at: an action with a decision in it
// (create this link, choose these columns, add this book).

/// Shows [html] as a page, hiding the library beneath it.
export function openPage(title, subtitle, html){
  closeModal();
  const page = document.getElementById('page');
  page.innerHTML = `
    <div class="pagehead">
      <button class="btn sm quiet" onclick="closePage()">← Library</button>
      <h2>${esc(title)}</h2>
      ${subtitle ? `<p class="muted">${esc(subtitle)}</p>` : ''}
    </div>
    <div class="pagebody">${html}</div>`;
  page.classList.remove('hidden');
  document.getElementById('tbl').classList.add('hidden');
  document.getElementById('loadmore').classList.add('hidden');
  // The library's own controls — search, filters, selection — belong to the
  // table that is no longer on screen.
  for (const bar of document.querySelectorAll('#topbar .toolbar')) {
    bar.classList.add('hidden');
  }
  window.scrollTo(0, 0);
}

export function closePage(){
  const page = document.getElementById('page');
  page.classList.add('hidden');
  page.innerHTML = '';
  document.getElementById('tbl').classList.remove('hidden');
  for (const bar of document.querySelectorAll('#topbar .toolbar')) {
    bar.classList.remove('hidden');
  }
  // The selection bar is only on screen while rows are selected; render()
  // decides that, not this.
  renderSelectionBar();
  render();
}

/// True while a page is open, so Escape closes the page rather than nothing.
export function pageOpen(){
  return !document.getElementById('page').classList.contains('hidden');
}
