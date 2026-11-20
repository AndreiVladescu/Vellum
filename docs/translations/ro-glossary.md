# Romanian glossary (ro)

The terms `app/lib/l10n/app_ro.arb` uses, and why. A change to a term here is a
change across the whole file: search the ARB for the old word and replace every
occurrence, or the app ends up saying two things for one idea.

## House style

| Decision | Choice | Why |
| --- | --- | --- |
| Form of address | **tu** (informal): „Adaugă”, „Ai mutat…”, „Ești conectat?” | Vellum is a personal app with a conversational English voice (“Your shelf is empty”, “You were on page 12”). *Dumneavoastră* („Adăugați”) reads like a bank or a tax form here, and is ~10–15% longer on buttons. The Material widgets Flutter supplies (date picker, „Anulați” in some system dialogs) use the formal form; that mix is common in Romanian Android apps and was accepted as the lesser cost. |
| Buttons and menu items | Imperative, 2nd person singular: „Salvează”, „Șterge”, „Importă” | Same choice as above. Titles of sections and settings are nouns: „Sincronizare”, „Copie de rezervă”. |
| Questions in dialog titles | 2nd person, present: „Ștergi acest exemplar?”, „Muți „X” în coș?” | Shorter and friendlier than „Doriți să ștergeți…?” |
| Capitalisation | Sentence case everywhere | Romanian does not use English title case. Language names are capitalised only because they are list items („Engleză”). |
| Quotation marks | „…” (U+201E … U+201D) | Romanian typography. Straight `"` stays only where it is literal syntax (the CSV example in `catalogHelpMultiBody`). |
| Dashes | Spaced en dash ` – ` for a pause, unspaced `–` for ranges (`1–20`) | The English uses an em dash; Romanian uses the en dash for both. |
| Percent | `42 %` with a no-break space (U+00A0) | CLDR and Romanian usage; also what `NumberFormat.percentPattern('ro')` produces, so hand-written and formatted percentages match. |
| Decimal separator | comma, from `intl` (`1,5`) | Never typed by hand; numbers reach the messages already formatted for the locale. |
| Dates and times | From `intl` (`20.11.2026`, `4 mar. 2026`, `14:05`) | Never hard-coded. Month names are lower case in Romanian („în octombrie”), which `DateFormat('MMMM', 'ro')` already does. |
| Units | `min`, `h`, `z` (zile) with a space: `3 h 20 min` | Romanian abbreviations; the space is required. |
| Diacritics | ș ț with comma below (U+0219, U+021B), never ş ţ with cedilla | The cedilla forms are the Turkish letters; `test/l10n_ro_test.dart` fails on them. |
| “I”/“we” in confirmations | „Ai adăugat „X” pe raft” rather than „„X” a fost adăugată” | The second form needs the book title's grammatical gender, which the app does not know. Addressing the reader is gender-free. |

## Plurals

Romanian has three CLDR plural forms and the app uses all three:

| Form | Numbers | Example |
| --- | --- | --- |
| `one` | 1 | 1 carte |
| `few` | 0, 2–19, and any number whose last two digits are 01–19 (101, 115, 1 002) | 2 cărți, 19 cărți, 101 cărți |
| `other` | 20–100, 120–200, … (last two digits 00 or 20–99) | **20 de cărți**, 100 de cărți, 1 000 de cărți |

The `de` belongs in `other` only. It applies to adjectives used alone too, which
is why a bare count is phrased without a noun where possible („{count}
selectate”) or keeps the noun with every form.

## Terms

| English | Romanian | Notes |
| --- | --- | --- |
| library | bibliotecă (biblioteci) | The collection, and a physical room-library („bibliotecă fizică”). |
| bookcase | corp de bibliotecă | IKEA Romania sells BILLY as a „bibliotecă”, but that would collide with *library*: „Ștergi toată biblioteca?” would read as deleting the collection. „Corp de bibliotecă” is the furniture term and is unambiguous. |
| shelf | raft (rafturi) | Both a custom collection (“New shelf”) and a physical board, as in English. „Pe raft” (on the shelf). |
| custom / personal / shared shelf | raft personal / partajat | |
| spine | cotor (cotoare) | „Cotorul la vedere” for spine-out. |
| front cover / cover | copertă (coperte) | „Coperta la vedere” for face-out. |
| dust jacket | supracopertă | |
| book | carte (cărți) | Feminine, so status adjectives agree: „necitită”, „terminată”. |
| physical copy | exemplar fizic (exemplare fizice) | „Exemplar” is the librarian's word for one copy of a title. |
| copy photo / condition photo | fotografie a exemplarului / fotografii cu starea cărții | |
| placement | amplasare | Where a copy sits in a room. |
| room | cameră | |
| side panel / divider / label | panou lateral / separator / etichetă | |
| stocktake | inventar | „Fă inventarul camerei”. |
| tidy (a shelf) | a pune în ordine | |
| loan | împrumut (împrumuturi) | |
| lend | a împrumuta (cuiva) | Button „Împrumută”, „Împrumutat lui Ion”. |
| borrow | a lua / a cere cu împrumut | Romanian uses *a împrumuta* for both directions; the context (or „cere cu împrumut”) carries the direction. |
| borrower | (persoana) căreia i-ai împrumutat | Never „împrumutător”, which means the *lender*. The field is labelled „Împrumutat lui”. |
| due date / due back | termen (de returnare) | „Termenul e mâine”, „Termen depășit cu 3 zile”. |
| overdue | termen depășit | |
| return (a loan) | a returna | Button „Returnează”; state „Returnată”. |
| borrow request | cerere de împrumut | |
| wishlist | listă de dorințe | Status label: „Dorită”. |
| reading status | starea lecturii | |
| unread / reading / finished / abandoned / reference | necitită / în lectură / terminată / abandonată / referință | Feminine, agreeing with *carte*. |
| rating, star | evaluare, stea (stele) | |
| series / volume | serie (serii) / volum | |
| genre / tag | gen (genuri) / etichetă | |
| author / publisher / year | autor / editură / anul apariției | |
| highlight (noun / verb) | evidențiere / a evidenția | Google's Romanian uses the same. „Marcaj” was rejected: it is what Chrome calls a browser bookmark. |
| highlighter | evidențiator | |
| note | notă (note) | An annotation attached to a passage. |
| reader notes (book page) | notițe | The personal notes box; „Notițele mele”. Kept distinct from *notă* so the two features do not share a name. |
| annotation | adnotare (adnotări) | Umbrella for highlights, notes, bookmarks, ink. |
| bookmark | semn de carte | Verb: „Marchează această pagină”. |
| ink / pen marks / writing | scris de mână, stilou, însemnări | |
| reading session / sitting | sesiune de lectură (sesiuni) | English uses both words; Romanian has one natural one. „Ședință” sounds like a meeting. |
| reading position | poziția de lectură | |
| progress | progres | |
| streak | zile la rând | *Serie* (Duolingo's word) is already *series*. „Zile la rând acum”, „Record de zile la rând”. |
| goal | obiectiv | „În grafic” / „înaintea graficului” / „în urma graficului” for on pace / ahead / behind. |
| Insights | Statistici de lectură | „Perspective” is a calque. *Library statistics* is „Statisticile bibliotecii”. |
| Year in review | Anul în cărți | Idiomatic; „Recapitularea anului” was the literal alternative. |
| Month by month | Lună de lună | |
| reader (the screen) | cititor; settings: „setările de citire” | |
| paged / scrolled | pe pagini / derulare continuă | PDF: „Pagini” / „Derulare”. |
| fit width / fit page | pe lățime / pagina întreagă | |
| page colour: light / sepia / grey / dark | deschis / sepia / gri / închis | Describes the page, not a theme („temă luminoasă/întunecată” is the app theme). |
| serif / sans / monospace | cu serife / fără serife / monospațiat | |
| auto-scroll | derulare automată | |
| read aloud (TTS) | citire cu voce tare | Engine: „motor de sinteză vocală”. |
| dictionary / look up | dicționar / a căuta | |
| translate / translator | a traduce / traducător | |
| language pack | pachet de limbi | |
| model (AI) | model AI | „Model” alone is too vague in Romanian. |
| audiobook | carte audio (cărți audio) | |
| narrator | narator | No message uses it yet; listed so the first one agrees. |
| chapter / part | capitol / parte (părți) | |
| playback speed / sleep timer | viteza de redare / temporizator de oprire | |
| now playing bar / player | player | Common loanword in Romanian UIs. |
| listening | ascultare | |
| sync | sincronizare / a sincroniza | |
| pull / push (sync) | a prelua / a trimite | „Preluate: 3, trimise: 4.” avoids agreeing with an unnamed noun. |
| server / library server | server / server de bibliotecă | |
| master account | cont principal | |
| sign in / log in / sign out | a se autentifica / a se deconecta | „Conectare” is kept for connecting to a server. |
| app password | parolă de aplicație | No message in the app uses it yet. |
| two-factor sign-in | autentificare în doi pași | Google's and Microsoft's Romanian name for it. |
| recovery codes | coduri de recuperare | |
| certificate / fingerprint / self-signed | certificat / amprentă / autosemnat | |
| share (with people) | a partaja; partajare | „Distribuie” is used only for handing a picture to another app (system share sheet). |
| public link | link public | |
| viewer / editor (permission) | cititor / editor | |
| backup / restore / export | copie de rezervă / a restaura / a exporta | |
| passphrase | frază de acces | |
| checksum | sumă de control | |
| trash | coș | „Mută în coș”, „Golește coșul”. |
| library health | starea bibliotecii | |
| duplicate / merge | duplicat / a îmbina | |
| import / scan | a importa / a scana | |
| folder / watched folder | dosar / dosar urmărit | Windows' Romanian says „folder”; Android and GNOME say „dosar”. |
| catalogue (OPDS) / feed | catalog / flux | |
| metadata | metadate | |
| barcode | cod de bare | |
| sample books | cărți de exemplu | |
| device | dispozitiv | „Calculator” when the English says *machine* or *computer*. |
| wallpaper | imagine de fundal | |
| Preferences | Preferințe | |
| notifications / status bar | notificări / bara de stare | |
| reminder | memento (mementouri) | |
| Undo / Cancel | Anulează | Romanian uses the same verb for both; the snack bar context makes Undo clear. |

## Not translated

Brand, product and protocol names stay as they are: Vellum, OPDS, KOReader,
Calibre, Calibre-Web, Kavita, EPUB, PDF, Docker, Goodreads, Open Library,
Project Gutenberg, Wikisource, WordNet, LibreTranslate, Argos, Apertium, Google
ML Kit, Material You, Ollama, OpenAI, Kindle. So do the CSV and JSON column names
(`title`, `books`), which are what the importer actually reads.
