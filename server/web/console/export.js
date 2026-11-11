// Export of the rows on screen as CSV or JSON.

import { S } from './state.js';
import { authorStr, bookTags, toast } from './dom.js';

// ---- export -------------------------------------------------------------

export function download(name, text, mime){
  const url = URL.createObjectURL(new Blob([text],{type:mime}));
  const a = document.createElement('a'); a.href=url; a.download=name; a.click();
  setTimeout(()=>URL.revokeObjectURL(url), 1000);
}
export function csvCell(v){
  if (v==null) v='';
  v = String(v);
  return /[",\n]/.test(v) ? '"'+v.replace(/"/g,'""')+'"' : v;
}
// Exports only cover what's loaded into S.books (§3's paged /api/books), so
// a library with more pages remaining needs "Load more" clicked first or the
// export silently leaves books out -- warn rather than let that pass quietly.
export function exportCaveat(){
  return S.nextPage == null ? '' : ` (${S.total-S.books.length} more not loaded — click "Load more" first for a full export)`;
}
export function exportJSON(){
  download('vellum-books.json', JSON.stringify(S.view, null, 2), 'application/json');
  toast('Exported '+S.view.length+' book(s)'+exportCaveat());
}
export function exportCSV(){
  const cols = ['title','subtitle','authors','published_year','publisher','isbn','page_count','file_count','has_cover','tags','created_at'];
  const lines = [cols.join(',')];
  for (const b of S.view){
    const rec = { ...b, authors:authorStr(b), has_cover: b.cover_path?'yes':'no',
                  tags: bookTags(b).map(g=>g.name).join('; ') };
    lines.push(cols.map(c=>csvCell(rec[c])).join(','));
  }
  download('vellum-books.csv', lines.join('\n'), 'text/csv');
  toast('Exported '+S.view.length+' book(s)'+exportCaveat());
}
