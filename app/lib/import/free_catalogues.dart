/// Catalogues of freely licensed books, so the OPDS browser opens with
/// somewhere to go instead of an empty box.
///
/// The browser has always been able to fetch a feed and download from it — what
/// it lacked was any way to know a URL. Nobody has an OPDS address memorised,
/// so the feature was effectively unreachable without one.
///
/// **Only sources that are free to redistribute.** Everything here is public
/// domain or open access. Shadow libraries are not listed and will not be: the
/// point of the picker is that following it cannot land anyone anywhere they
/// should not be.
///
/// Each entry was fetched and its acquisition links inspected before being
/// added — a catalogue that browses but hands back HTML instead of an EPUB is
/// worse than no entry at all.
library;

/// One catalogue, as offered in the picker.
class FreeCatalogue {
  const FreeCatalogue({
    required this.name,
    required this.url,
    required this.description,
  });

  final String name;
  final String url;

  /// What is in it and what to expect — shown under the name, because "Project
  /// Gutenberg" tells you nothing about whether it has the book you want.
  final String description;
}

/// The offered catalogues, best first.
///
/// Deliberately short. A list of thirty half-working feeds is a worse answer
/// than three that are known to work, and every entry here costs someone a
/// disappointment if it rots.
const freeCatalogues = <FreeCatalogue>[
  FreeCatalogue(
    name: 'Project Gutenberg',
    url: 'https://www.gutenberg.org/ebooks.opds/',
    description:
        'Around 75,000 public-domain books, as EPUB with covers. The largest '
        'of the free catalogues and the one most likely to have a classic you '
        'are missing.',
  ),
  FreeCatalogue(
    name: 'Wikisource',
    url: 'https://ws-export.wmcloud.org/opds/en/Ready_for_export.xml',
    description:
        'Around 700 English titles proofread by Wikisource volunteers and '
        'marked ready for export. Smaller than Gutenberg, and strong on '
        'documents and speeches rather than novels.',
  ),
  // Feeds that need a login (Standard Ebooks' OPDS is behind its Patrons
  // Circle) or that answer 403 to a plain client (Feedbooks, ManyBooks,
  // Gallica — the last returns 200 with "Access Denied" in the body) are left
  // out on purpose: an entry that fails on the first tap teaches you the
  // feature is broken. Standard Ebooks' books are freely downloadable from its
  // website — only the feed is gated — so it belongs here if that changes.
];
