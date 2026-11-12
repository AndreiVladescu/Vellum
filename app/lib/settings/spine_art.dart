/// How a spine-out book with cover art draws its spine. Only meaningful in
/// [BookFace.spine] mode — face-out books always show the cover itself.
enum SpineArt {
  /// A vertical slice of the cover image (the default) — real spines usually
  /// continue the cover's artwork.
  coverSlice,

  /// A generated spine coloured with the cover's dominant colour — a tidier,
  /// more uniform shelf.
  dominantColor;
}
