# Sample books

Bundled for the "Try it with a few sample books" action (first-run sheet and the
empty shelf). All four are [Standard Ebooks](https://standardebooks.org)
productions, downloaded unmodified from their "recommended compatible" EPUB link
(`.../downloads/<name>.epub?source=download`).

Licence: the underlying texts are in the public domain in the United States, and
Standard Ebooks dedicates its own production work (typography, markup, cover) to
the public domain under CC0 1.0
(<https://creativecommons.org/publicdomain/zero/1.0/>).

| File | Size | Source page |
| --- | --- | --- |
| `the-importance-of-being-earnest.epub` | 419 KB | https://standardebooks.org/ebooks/oscar-wilde/the-importance-of-being-earnest |
| `the-time-machine.epub` | 536 KB | https://standardebooks.org/ebooks/h-g-wells/the-time-machine |
| `frankenstein.epub` | 686 KB | https://standardebooks.org/ebooks/mary-shelley/frankenstein |
| `the-adventures-of-sherlock-holmes.epub` | 742 KB | https://standardebooks.org/ebooks/arthur-conan-doyle/the-adventures-of-sherlock-holmes |

Total: about 2.4 MB. Each declares its cover image in the package file, which
the import picks up. Title, author and year shown in the app come from
`lib/onboarding/sample_library.dart`, not from the EPUB (whose date is the
edition's, not the book's).

Do not edit these files: the app recognises a sample by the sha256 of its bytes.
