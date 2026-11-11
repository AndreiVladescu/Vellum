// The console's shared state: the one object every page reads and writes.

// The bearer token lives in sessionStorage, not localStorage (plan 5 #35,
// §0.12): a token stolen through an XSS then dies with the tab instead of
// persisting across every future visit. The CSP already blocks the obvious
// exfiltration paths, so this is defence in depth rather than a fix for a known
// hole — the cost is signing in again in a new tab, which is the right trade for
// a management console.
export const S = { token: sessionStorage.getItem('vellum_token'), email: sessionStorage.getItem('vellum_email'),
            books: [], groups: [], members: new Set(), selected: new Set(),
            view: [], cursor: -1,
            // /api/books?page=1 (§3) loads the library a page at a time instead
            // of unbounded; nextPage is the next page to fetch via "Load more",
            // null once every book is loaded. total is the server's count of
            // every visible book, independent of how many pages are in S.books.
            nextPage: 1, total: 0,
            // Search, sort and filters are now *server-side* (plan 5 #35): a
            // 10,000-book library shouldn't have to reach the browser before it
            // can be narrowed. One tag and one "missing" at a time, which is
            // what the server takes and what people actually use.
            q: '', sort: { col: 'title', dir: 'asc' },
            fTag: null, fMissing: null,
            cols: new Set(JSON.parse(localStorage.getItem('vellum_cols') || 'null') || ['author','year','status']),
            compact: localStorage.getItem('vellum_density') === '1' };

// Columns the user can show or hide (the checkbox, title, tags and actions
// columns are always present).
export const OPT_COLS = [['cover','Cover thumbnail'],['author','Author'],['year','Year'],
                  ['pages','Pages'],['status','Files'],['added','Date added'],
                  // Off unless asked for: on a library of one it is the same
                  // name on every row.
                  ['owner','Added by']];
