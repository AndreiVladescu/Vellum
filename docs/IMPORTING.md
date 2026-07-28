# Importing books in bulk

Vellum takes books four ways. Which one you want depends on whether you have
the *files* or only a *list*.

| You have | Use | Brings files |
|---|---|---|
| A folder of PDFs and EPUBs | **A folder of files** | Yes |
| A Calibre library | **A Calibre library** | Yes, with covers |
| A spreadsheet, or an export from Goodreads/StoryGraph/the Vellum console | **A CSV or JSON catalogue** | No — records only |
| Another server's catalogue | **An OPDS catalogue** | Yes, what you pick |

All four end at the same review screen, which shows what was found and what
looks like something you already have, before anything is added.

A CSV import creates books with no file attached. That is a real import, not a
degraded one — a record of physical books, or of a library whose files live
elsewhere, is still a library. You can attach files to those books afterwards,
or run a folder import over the same books and let the duplicate check join
them up.

---

## A CSV or JSON catalogue

### The short version

One header row, one book per row, a column called `title`. Everything else is
optional.

```csv
title,authors,published_year,publisher,isbn,page_count,series,series_index,tags,description
The Left Hand of Darkness,Ursula K. Le Guin,1969,Ace Books,9780441007318,304,Hainish Cycle,4,"science fiction; classics",A envoy to a world without fixed gender.
Piranesi,Susanna Clarke,2020,Bloomsbury,9781635575637,272,,,fantasy,A man lives in an infinite house of statues.
```

Save it as UTF-8. The reader is RFC 4180: wrap a field in `"` if it contains a
comma, a newline or a quote, and double a literal quote (`""`).

### Columns

The header decides which column is which, so **order does not matter** and
columns Vellum doesn't recognise are ignored — you can import an export from
somewhere else without editing it first.

| Meaning | Header, or any of these aliases |
|---|---|
| **Title** (required) | `title`, `book title` |
| Author(s) | `authors`, `author`, `author_sort`, `creator` |
| Subtitle | `subtitle` |
| ISBN | `isbn`, `isbn13`, `isbn-13`, `isbn_13` |
| Publisher | `publisher` |
| Year | `published_year`, `year`, `year published`, `original publication year` |
| Pages | `page_count`, `pages`, `number of pages` |
| Series | `series` |
| Number in series | `series_index`, `volume` |
| Genres / tags | `tags`, `genres`, `bookshelves`, `subjects` |
| Description | `description`, `comments`, `summary` |

Headers are matched case-insensitively and with surrounding spaces ignored, so
`Title`, `title` and ` TITLE ` are the same column.

### Values

- **Several authors or tags in one cell** — separate with `;`, `,` or ` & `:
  `Terry Pratchett & Neil Gaiman`, or `"fantasy; humour; 1990s"`. Remember the
  quotes if you use commas inside a CSV cell.
- **ISBN** — punctuation and spaces are stripped, so `978-0-441-00731-8` is
  fine. Goodreads' Excel-armoured `="9780441007318"` is understood too.
  Anything that isn't 10 or 13 characters after cleaning is dropped rather than
  stored wrong.
- **Year** and **pages** — plain integers. Anything unparseable is left empty.
- **Series index** — may be fractional (`1.5` for a novella between books).
- **Empty cells** are simply absent; they don't overwrite anything.

### What gets rejected

- A file with **no title column** is refused outright. Without one, every row
  would import as a book named after its ISBN, and the honest failure is
  better than a library you then have to unpick.
- **Rows with an empty title** are skipped; the rest of the file still imports.
- A file where **no row has a title** is refused for the same reason.

### JSON instead

The format is chosen by the file's first non-space character, not its
extension — a `.txt` holding JSON is still JSON. Either shape works:

```json
[
  { "title": "Piranesi", "authors": ["Susanna Clarke"], "published_year": 2020 }
]
```

```json
{ "books": [ { "title": "Piranesi" } ] }
```

Keys use the same names and aliases as the CSV headers. `authors` and `tags`
may be real JSON arrays, or the same joined strings the CSV uses.

### Exports from elsewhere

- **The Vellum console** (`/api/books`, or its CSV export) round-trips: export
  from one library, import into another, and you get the same books.
- **Goodreads** — export from *My Books → Import and export*. Its `Title`,
  `Author`, `ISBN13`, `Number of Pages`, `Year Published`, `Publisher`,
  `Bookshelves` and `My Review` columns all land in the right place.
- **StoryGraph** and **LibraryThing** exports use the same common names and
  need no editing either.

If an export uses a column name Vellum doesn't know, renaming that one header
is usually the whole job.

---

## A folder of files

Point Vellum at a folder and it reads every PDF and EPUB inside it, including
subfolders. Metadata comes from the file *name*, so naming pays off:

```
Author - Title-Publisher (Year).epub
```

Every part is optional and it degrades gracefully:

| File name | Becomes |
|---|---|
| `Ursula K. Le Guin - The Dispossessed-Harper (1974).epub` | author, title, publisher, year |
| `Ursula K. Le Guin - The Dispossessed (1974).epub` | author, title, year |
| `Ursula K. Le Guin - The Dispossessed.epub` | author, title |
| `The Dispossessed.epub` | title only |

- Authors run up to the first ` - ` and may be separated by `,` or `&`.
- A trailing `(YYYY)` is read as the year.
- In what's left, the **last** `-` splits title from publisher — so a title
  containing a hyphen is safe as long as the publisher comes after it.

Anything that fits none of the pattern becomes the title as-is, and the online
lookup on the review screen usually recovers the rest from that.

---

## After the scan

Whatever the source, the review screen lists every book found, marks the ones
that look like something already in the library, and lets you deselect any of
them. Nothing is written until you confirm.

Importing a large catalogue also fetches metadata and covers for the books that
need them, which is the slow part; it can be stopped at any point and what has
already been imported stays.
