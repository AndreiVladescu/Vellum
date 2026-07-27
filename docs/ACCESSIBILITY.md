# Accessibility

What Vellum guarantees, what is verified automatically, and the manual checks
that no test can do. Written for plan 5 #42; keep it current when adding UI, or
this drifts the way the first round did.

## The rules

1. **Every interactive thing is keyboard-reachable.** A bare `GestureDetector`
   is not: it takes no focus and answers no key. Use `InkWell`, a `*Button`, or
   an explicit `Focus` + `Actions`. This is why book spines are `InkWell`s —
   they are the shelf's only way into a book, and for a while they could not be
   reached without a mouse.
2. **Tap targets are ≥ 48 dp.** Guaranteed globally by
   `materialTapTargetSize: MaterialTapTargetSize.padded` in `vellumThemes`, on
   every platform rather than only on mobile.
3. **Icon-only controls carry a tooltip**, which is also their semantic label.
4. **Anything painted rather than laid out needs a parallel representation.**
   A `CustomPaint` is invisible to a screen reader. See the room canvas below.
5. **Long silent operations announce.** A progress bar says nothing out loud.

## Verified by tests

`app/test/a11y_semantics_test.dart` and `app/test/physical/room_semantics_test.dart`:

- book spines and covers expose a title (plus subtitle) and are focusable
- the cover thumbnail is a labelled, focusable button
- the room canvas reports one node summarising every shelf and its books
- the room summary orders shelves top-to-bottom and books left-to-right, and
  never silently drops a book that is on no shelf
- large-text (2× `textScaler`) renders the shelf and detail page without
  overflow — `app/test/widgets/large_text_test.dart`

## Manual checks (no test can do these)

Run these against a real screen reader after touching the relevant screen.
**TalkBack** on Android, **Orca** on Linux, **VoiceOver** on macOS.

### The shelf
1. Swipe/arrow through the shelf. Each book announces its title, and the
   subtitle when it has one — not "button" alone, and not the spine artwork.
2. Tab through with a keyboard only. Every spine takes focus, shows a visible
   focus overlay, and opens on Enter or Space.
3. Turn on 2× text size. The shelf still packs into rows and nothing clips.

### The physical room editor
4. Focus the canvas. It reads as one node: *"Shelf 1: 3 books — Dune,
   Neuromancer, Solaris. Shelf 2: empty"*, then the hint about Room contents.
5. Individual spines inside the canvas must **not** announce themselves — they
   have no meaningful order, which is the whole reason for the summary.
6. Open **Room contents** from the toolbar. Each shelf is its own list item and
   reads the same as the summary said.

### Sync
7. Start a sync with a screen reader on. Each *phase* is announced once
   ("Pushing books"), not once per book, and the result is announced at the
   end — including "Already up to date."

### The readers
8. PDF and EPUB: the page/chapter controls, the settings sheet, and the
   annotations panel are all reachable by keyboard and labelled.
9. Reader settings at 2× text: the sliders and their labels do not overlap.

### Sharing and the server page
10. The share sheet's switches announce their state, and the certificate
    fingerprint is readable as text rather than only visually comparable.

## Known gaps

- **The room canvas is not directly navigable**, deliberately. A drag-and-drop
  spatial arrangement has no useful traversal order; *Room contents* is the
  navigable equivalent and is a first-class toolbar action rather than an
  accessibility afterthought.
- **Drag-and-drop has no keyboard equivalent.** Placing a book in a room needs
  a pointer. *Tidy this shelf* (plan 5 #28) is the keyboard-reachable way to
  arrange books; free placement is not.
- The reader screens have had a large-text pass but not a full screen-reader
  pass; items 8–9 above are the checklist for when they do.
