// Table preferences: columns, density, and saved views.

import { OPT_COLS, S } from './state.js';
import { esc, key, toast } from './dom.js';
import { ask } from './dialogs.js';
import { reload, renderFilters, showLabelIf } from './books.js';
import { render } from './table.js';

// ---- columns + density --------------------------------------------------

export function openColumns(){
  document.getElementById('modal-root').innerHTML = `
   <div class="modal-bg" onclick="if(event.target===this)closeModal()">
    <div class="modal">
      <h2>Columns</h2>
      <div class="colgrid">
        ${OPT_COLS.map(([k,l])=>`<label><input type="checkbox" ${S.cols.has(k)?'checked':''} data-changeact="togglecol" data-key="${esc(k)}">${l}</label>`).join('')}
      </div>
      <div class="row"><button class="btn primary" onclick="closeModal()">Done</button></div>
    </div>
   </div>`;
}
export function toggleCol(k, on){
  on ? S.cols.add(k) : S.cols.delete(k);
  localStorage.setItem('vellum_cols', JSON.stringify([...S.cols]));
  render();
}
export function toggleDensity(){
  S.compact = !S.compact;
  localStorage.setItem('vellum_density', S.compact?'1':'0');
  document.getElementById('tbl').classList.toggle('compact', S.compact);
}

// ---- saved views (plan 5 #35) -------------------------------------------
//
// A view is a name for "how I like to look at the library": the search text,
// the tag and missing filters, the sort, and which columns are shown. Kept in
// localStorage rather than on the server on purpose — it is a *browser*
// preference, like the density toggle, and putting it on the server would mean
// a schema, an endpoint and a sync story for something nobody shares.

export function savedViews(){
  try { return JSON.parse(localStorage.getItem('vellum_views') || '[]'); }
  catch(_){ return []; }
}

export async function saveView(){
  const answer = await ask({
    title: 'Save this view',
    body: 'The current search, filters, sort and columns, under a name.',
    fields: [{ label: 'Name', placeholder: 'Unread technical' }],
    confirmLabel: 'Save',
  });
  const name = answer ? answer[0] : '';
  if (!name) return;
  const views = savedViews().filter(v => v.name !== name); // overwrite by name
  views.push({
    name,
    q: S.q, sort: { ...S.sort }, tag: S.fTag, missing: S.fMissing,
    cols: [...S.cols],
  });
  localStorage.setItem('vellum_views', JSON.stringify(views));
  renderViews();
  toast('Saved “' + name + '”');
}

export function applyView(name){
  const view = savedViews().find(v => v.name === name);
  if (!view) return;
  S.q = view.q || '';
  document.getElementById('q').value = S.q;
  S.sort = view.sort || { col:'title', dir:'asc' };
  S.fTag = view.tag || null;
  S.fMissing = view.missing || null;
  if (view.cols) { S.cols = new Set(view.cols); localStorage.setItem('vellum_cols', JSON.stringify([...S.cols])); }
  renderFilters(); renderViews(); reload();
}

export function deleteView(name){
  localStorage.setItem('vellum_views',
    JSON.stringify(savedViews().filter(v => v.name !== name)));
  renderViews();
}

export function renderViews(){
  const host = document.getElementById('views');
  if (!host) return;
  const views = savedViews();
  // No saved views means no "Views:" label — it would introduce a heading for
  // an empty space, which is how the filter row came to look busy.
  showLabelIf('viewslabel', views.length > 0);
  host.innerHTML = views.map(v =>
    `<span class="fchip">
       <span class="link" data-act="applyview" data-name="${esc(v.name)}">${esc(v.name)}</span>
       <button title="Forget this view" data-act="deleteview" data-name="${esc(v.name)}">×</button>
     </span>`).join('');
}
