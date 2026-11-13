// The console's entry point, loaded as <script type="module">.
//
// Every module is listed here, in a fixed order, for two readers: the browser,
// which needs nothing more than the import graph, and the Node tests, which read
// this list to load the same files as one classic script
// (tests/console_source.js). A module that is not imported here is never loaded.

import * as stateModule from './state.js';
import * as domModule from './dom.js';
import * as apiModule from './api.js';
import * as dialogsModule from './dialogs.js';
import * as pagesModule from './pages.js';
import * as menusModule from './menus.js';
import * as actionsModule from './actions.js';
import * as sessionModule from './session.js';
import * as firstRunModule from './first_run.js';
import * as booksModule from './books.js';
import * as tableModule from './table.js';
import * as viewsModule from './views.js';
import * as exportModule from './export.js';
import * as addBookModule from './add_book.js';
import * as importModule from './import.js';
import * as uploadsModule from './uploads.js';
import * as tagsModule from './tags.js';
import * as bulkModule from './bulk.js';
import * as detailModule from './detail.js';
import * as linksModule from './links.js';
import * as certModule from './cert.js';
import * as requestsModule from './requests.js';
import * as loansModule from './loans.js';
import * as remindersModule from './reminders.js';
import * as roomsModule from './rooms.js';
import * as sharesModule from './shares.js';
import * as peopleModule from './people.js';
import * as appPasswordsModule from './app_passwords.js';
import * as securityModule from './security.js';
import * as mailModule from './mail.js';
import * as overviewModule from './overview.js';
import * as serverModule from './server.js';
import * as activityModule from './activity.js';
import * as searchModule from './search.js';
import * as routerModule from './router.js';
import { start } from './boot.js';

// Inline handlers — `onclick="login()"` in console.html and in the markup the
// pages build — are looked up on `window`, and a module's functions are not
// globals. Before the split every function was one, so they are put back here,
// all of them, rather than a hand-kept list that would miss the one handler
// nobody remembered. Functions only: a copied `let` would go stale.
const modules = [
  stateModule, domModule, apiModule, dialogsModule,
  pagesModule, menusModule, actionsModule, sessionModule,
  firstRunModule, booksModule, tableModule, viewsModule,
  exportModule, addBookModule, importModule, uploadsModule,
  tagsModule, bulkModule, detailModule, linksModule,
  certModule, requestsModule, loansModule, remindersModule,
  roomsModule, sharesModule, peopleModule, appPasswordsModule, securityModule, mailModule,
  overviewModule, serverModule, activityModule, searchModule, routerModule,
];
for (const mod of modules) {
  for (const [name, value] of Object.entries(mod)) {
    if (typeof value === 'function') window[name] = value;
  }
}

start();
