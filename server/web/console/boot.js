// Everything the console does at load: the delegated listeners, the keyboard,
// and deciding whether to show the console or the sign-in. One function rather
// than top-level statements so main.js can run it *after* it has put the
// handlers on `window` (see there), and in the same order the single script did.

import { S } from './state.js';
import { closeModal } from './dialogs.js';
import { pageOpen } from './pages.js';
import { closeMenus } from './menus.js';
import { ACTIONS, CHANGE_ACTIONS, DBL_ACTIONS, delegate } from './actions.js';
import { showApp } from './session.js';
import { checkRegistration } from './first_run.js';
import { afterCursorMove, syncStickyHead, toggleRow } from './table.js';
import { dropOn } from './uploads.js';
import { openDetail } from './detail.js';
import { closeNav, go, HOME, navOpen } from './router.js';

export function start(){
  delegate('click', ACTIONS, 'data-act');
  delegate('dblclick', DBL_ACTIONS, 'data-dblact');
  delegate('change', CHANGE_ACTIONS, 'data-changeact');
  document.addEventListener('drop', ev => {
    const el = ev.target.closest('[data-dropbook]');
    if (el) dropOn(ev, el.dataset.dropbook, el);
  });

  // ---- keyboard navigation ------------------------------------------------

  document.addEventListener('keydown', e=>{
    if (!document.getElementById('login').classList.contains('hidden')) return;   // logged out
    const modalOpen = document.getElementById('modal-root').innerHTML !== '';
    // The collapsed nav is the topmost thing on screen when it is open, so
    // Escape closes it before it closes anything under it.
    if (e.key === 'Escape' && !modalOpen && navOpen()){ closeNav(true); return; }
    if (pageOpen() && !modalOpen && e.key !== 'Escape') return;
    if (e.key === 'Escape'){
      if (modalOpen) closeModal();
      else if (pageOpen()) go(HOME);           // through the address, so Back returns
      return;
    }
    if (modalOpen) return;
    const t = e.target, tag = (t.tagName||'').toLowerCase();
    if (tag==='input' || tag==='textarea' || tag==='select' || t.isContentEditable) return;

    if (e.key === '/'){ e.preventDefault(); document.getElementById('q').focus(); return; }
    // Arrows, space and Enter belong to the table — not to a focused nav link,
    // where Enter has to follow the link rather than also open a book.
    if (t.closest && t.closest('#nav')) return;
    if (!S.view.length) return;
    if (e.key === 'ArrowDown'){ e.preventDefault(); S.cursor = Math.min(S.view.length-1, S.cursor+1); afterCursorMove(); }
    else if (e.key === 'ArrowUp'){ e.preventDefault(); S.cursor = Math.max(0, S.cursor<0?0:S.cursor-1); afterCursorMove(); }
    else if (e.key === ' ' && S.cursor>=0){ e.preventDefault(); const id=S.view[S.cursor].id; toggleRow(id, !S.selected.has(id)); }
    else if (e.key === 'Enter' && S.cursor>=0){ openDetail(S.view[S.cursor].id); }
  });

  window.addEventListener('resize', ()=>{
    const tb = document.getElementById('topbar');
    if (tb) document.documentElement.style.setProperty('--thead-top', tb.offsetHeight+'px');
  });

  // boot
  if (S.token) showApp(); else checkRegistration();

  document.addEventListener('click', closeMenus);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeMenus(); });

  addEventListener('resize', syncStickyHead);
}
