-- Speeds up the per-book author/genre lookups books::list scopes to the
-- returned ids (plan 5 #3) -- both tables were scanned by book_id with no
-- supporting index.
CREATE INDEX IF NOT EXISTS idx_book_author_book ON book_author(book_id);
CREATE INDEX IF NOT EXISTS idx_book_genre_book ON book_genre(book_id);
