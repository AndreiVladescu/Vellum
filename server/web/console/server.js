// The Server page: version, storage, configuration, and the maintenance that
// used to be reachable only with curl.

import { esc, toast } from './dom.js';
import { api, downloadPath, settle } from './api.js';
import { ask } from './dialogs.js';
import { openPage } from './pages.js';

// ---- Server (plan 5 #37, now the one place to look after the server) -------
//
// Deliberately small: for a personal server, "how big is my library, how much
// disk is it using, is it backed up" is the question an operator actually has,
// and a metrics stack would be more machinery than the thing it observes.
// It replaced a Statistics page; that address still opens this one.

export const RELEASES_URL = 'https://github.com/AndreiVladescu/Vellum/releases';

export function fmtBytes(n){
  if (!n) return '0 B';
  const units = ['B','KB','MB','GB','TB'];
  let i = 0, v = n;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(1)) + ' ' + units[i];
}

/// How many paths a report lists before saying "and N more": a library that has
/// never been swept can have thousands, and a page of them helps nobody.
const SWEEP_SHOWN = 10;

/// The label and value of each setting in effect, in reading order. Booleans are
/// words, not true/false; the server only ever sends secrets as booleans.
export function configRows(cfg){
  const yn = (v, on, off) => (v ? on : off);
  return [
    ['Port', String(cfg.port)],
    ['Public URL', cfg.public_url],
    ['Data folder', cfg.data_dir],
    ['Database file', cfg.database_path],
    ['Largest upload', cfg.max_upload_mb + ' MB'],
    ['HTTPS (built-in TLS)', yn(cfg.tls, 'on', 'off — use a reverse proxy for HTTPS')],
    ['Email', yn(cfg.mail, 'configured', 'not configured')],
    ['Searching inside books', yn(cfg.text_indexing, 'on', 'off (VELLUM_INDEX_TEXT=1)')],
    ['Activity log', yn(cfg.audit_log, 'on', 'off (VELLUM_AUDIT=1)')],
    ['First-account token', yn(cfg.bootstrap_token, 'required to register the first account', 'not set')],
  ];
}

/// What the integrity check found, as a sentence per finding. Nothing here has
/// been deleted unless `report.deleted` says so.
export function sweepSummary(report){
  const lines = [];
  const missing = (report.missing_files || []).length;
  const covers = (report.missing_covers || []).length;
  const orphans = (report.orphan_blobs || []).length;
  if (missing) lines.push(`${missing} attached ${missing === 1 ? 'file is' : 'files are'} missing from disk.`);
  if (covers) lines.push(`${covers} ${covers === 1 ? 'cover is' : 'covers are'} missing from disk.`);
  if (orphans) lines.push(`${orphans} ${orphans === 1 ? 'file on disk is' : 'files on disk are'} used by no book (${fmtBytes(report.orphan_bytes)}).`);
  if (!lines.length) lines.push('Nothing is out of step: every file the database knows about is on disk, and every file on disk belongs to a book.');
  return lines;
}

/// The confirmation shown before anything is deleted: what goes, how many, how
/// much, and that it cannot be undone.
export function sweepConfirmBody(report){
  const n = (report.orphan_blobs || []).length;
  return `This permanently deletes ${n} ${n === 1 ? 'file' : 'files'} (${fmtBytes(report.orphan_bytes)}) `
    + 'that no book refers to. Books, covers and the database are not touched. '
    + 'It cannot be undone, so download a backup first if you are unsure.';
}

function pathList(title, list){
  if (!list || !list.length) return '';
  const shown = list.slice(0, SWEEP_SHOWN).map(p => `<li><code>${esc(p)}</code></li>`).join('');
  const rest = list.length > SWEEP_SHOWN ? `<li class="muted">and ${list.length - SWEEP_SHOWN} more</li>` : '';
  return `<p class="ov-sub">${esc(title)}</p><ul class="pathlist">${shown}${rest}</ul>`;
}

/// The report, as markup. The destructive button appears only when there is
/// something to delete, and only until it has been used.
export function sweepHtml(report){
  const summary = sweepSummary(report).map(l => `<p style="margin:0 0 4px">${esc(l)}</p>`).join('');
  const deleted = report.deleted
    ? `<p style="margin:8px 0 0"><strong>Deleted ${report.deleted} ${report.deleted === 1 ? 'file' : 'files'}.</strong></p>` : '';
  const canDelete = !report.deleted && (report.orphan_blobs || []).length > 0;
  return summary + deleted
    + pathList('Missing attached files (nothing was changed; restore them from a backup or upload them again)', report.missing_files)
    + pathList('Missing covers', report.missing_covers)
    + pathList('Used by no book', report.orphan_blobs)
    + (canDelete
      ? `<div class="row" style="margin-top:10px"><button class="btn sm danger" data-act="sweepdelete">Delete these files…</button></div>`
      : '');
}

function line(k, v){
  return `<div class="row" style="justify-content:space-between; gap:16px;
      padding:6px 0; border-bottom:1px solid var(--line)">
      <span>${esc(k)}</span><strong style="text-align:right; overflow-wrap:anywhere">${esc(String(v))}</strong></div>`;
}

function block(title, inner){
  return `<section class="ov-section"><h3>${esc(title)}</h3>${inner}</section>`;
}

/// The page body from settled answers `{ ok, data }` for each endpoint.
export function serverHtml(r){
  const parts = [];

  // Version. The latest release is not looked up: the server does not call out,
  // and the browser calling GitHub on its own would tell GitHub who runs this
  // and where. A link is the honest version of "check for updates".
  const caps = r.caps.ok ? r.caps.data : null;
  const version = (caps && caps.server_version) || (r.stats.ok && r.stats.data.server_version) || 'unknown';
  const feats = caps && Array.isArray(caps.features)
    ? `<p class="muted" style="margin:10px 0 4px">Features this server offers</p>
       <div>${caps.features.map(f => `<span class="chip">${esc(f)}</span>`).join('')}</div>` : '';
  parts.push(block('Version',
    line('Running', 'Vellum server ' + version)
      + (caps ? line('Sync protocol', caps.sync_protocol) : '')
      + `<p class="muted" style="margin:10px 0 0">To see whether a newer version exists, open the
          <a href="${esc(RELEASES_URL)}" target="_blank" rel="noopener noreferrer">releases page</a>
          and compare. This server never checks by itself.</p>`
      + feats));

  if (r.stats.ok){
    const s = r.stats.data;
    parts.push(block('Storage',
      line('Books', s.books) + line('Authors', s.authors) + line('Accounts', s.users)
      + line('Attached files', s.files) + line('Shares', s.shares) + line('Public links', s.share_links)
      + line('Book files and covers on disk', fmtBytes(s.blob_bytes))
      + line('Database (including WAL)', fmtBytes(s.database_bytes))));
  } else {
    parts.push(block('Storage', `<p class="muted">Could not load this: ${esc(r.stats.message)}</p>`));
  }

  parts.push(block('Maintenance', `
    <p style="margin:0 0 4px"><strong>Backup</strong></p>
    <p class="muted" style="margin:0 0 8px">One archive with a consistent copy of the
      database and every cover and book file. It is built on the server first, then
      downloaded; for a very large library, <code>curl</code> (see the deployment guide)
      streams it without holding it in the browser.</p>
    <button class="btn" data-act="downloadbackup">Download a backup</button>
    <p style="margin:18px 0 4px"><strong>Orphaned files</strong></p>
    <p class="muted" style="margin:0 0 8px">Compares the database with the files on disk.
      Checking changes nothing; deleting is a separate step you confirm.</p>
    <button class="btn" data-act="sweepcheck">Check for orphaned files</button>
    <div id="sweep-report" style="margin-top:10px" aria-live="polite"></div>`));

  if (r.config.ok){
    parts.push(block('Configuration in effect',
      configRows(r.config.data).map(([k, v]) => line(k, v)).join('')
      + `<p class="muted" style="margin:10px 0 0">Read-only. These come from the server's
        environment and change only by editing it and restarting. Secrets are never shown.</p>`));
  }

  parts.push(`<p class="muted" style="margin:18px 0 0">Every response carries an
    <code>X-Request-Id</code>; quote it when reporting a problem and it can be found in the
    server log.</p>`);
  return parts.join('');
}

export async function showServer(){
  const [stats, config, caps] = await Promise.all([
    settle(api('GET', '/api/admin/stats')),
    settle(api('GET', '/api/admin/config')),
    settle(api('GET', '/api/capabilities')),
  ]);
  // Only the master may read the numbers; say so rather than showing a raw 403.
  if (!stats.ok && stats.status === 403){
    toast('Only the library owner can see the server page.');
    return;
  }
  openPage('Server', 'The running server: its version, what it holds, and how to look after it.',
    serverHtml({ stats, config, caps }));
}

let lastSweep = null;

function showSweep(report){
  lastSweep = report;
  const host = document.getElementById('sweep-report');
  if (host) host.innerHTML = sweepHtml(report);
}

export async function checkOrphans(){
  try { showSweep(await api('POST', '/api/admin/sweep')); }
  catch(e){ toast(e.message); }
}

export async function deleteOrphans(){
  if (!lastSweep || !(lastSweep.orphan_blobs || []).length) return;
  const ok = await ask({
    title: 'Delete orphaned files?',
    body: sweepConfirmBody(lastSweep),
    confirmLabel: 'Delete',
    danger: true,
  });
  if (!ok) return;
  try { showSweep(await api('POST', '/api/admin/sweep?delete_orphans=true')); }
  catch(e){ toast(e.message); }
}

export async function downloadBackup(){
  const d = new Date();
  const p = n => String(n).padStart(2, '0');
  const name = `vellum-backup-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-`
    + `${p(d.getHours())}${p(d.getMinutes())}.tar`;
  toast('Preparing the backup — this can take a while.');
  if (await downloadPath('/api/admin/snapshot', name)) toast('Backup downloaded.');
}
