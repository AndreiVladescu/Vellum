# `layout_doc` v1 — the physical-room document format

A published room (plan 5 #47) travels as one versioned JSON document. This file
is the contract: the app writes it, the server stores it verbatim, and both the
app and the console read it.

## Why a document and not rows

Everything else Vellum syncs is a row with a `updated_at` and last-write-wins.
A room is not: it is a *composition*, and two devices that each moved half the
books do not have a meaningful merge. Row-level LWW would silently interleave
two arrangements into a third that neither person made.

So a layout is published **whole**, with a revision counter. A publish carries
the `base_revision` it started from; the server rejects it with **409** if
someone else published in between, and the app asks the human which arrangement
wins. That is the honest answer to a conflict here — see §J of the improvement
plan, where field-level merge is rejected for the same reason.

## Why the document carries no book metadata

The doc holds **geometry only**: rectangles, positions, and the ids they belong
to. No titles, no authors, no covers, no ISBNs.

This is what makes the console's room view (#48) safe by construction. A viewer
resolves each `book_id` through the normal RBAC path; a book they may not see
renders as an anonymous spine because *there was never anything else in the
document to leak*. Redaction is structural, not a filter someone has to
remember to apply.

The cost is one denormalisation: `width_m` and `height_m` are **baked in at
publish time**. A viewer who cannot see a book still needs to draw its spine at
the right thickness, and they cannot derive that from a page count they are not
allowed to read.

## The format

```jsonc
{
  "doc": "vellum.layout",
  "version": 1,
  "environment": {
    "id": "b3f1…",            // the environment's UUID, minted by the app
    "name": "Living room"
  },
  "shelves": [
    {
      "id": "8a2c…",
      "x1": 0.10, "y1": 1.20,  // metres, world coordinates, Y up
      "x2": 1.90, "y2": 1.20,
      "label": "Shelf 2",      // optional
      "kind": "shelf"          // shelf | panel | divider | label (#29)
    }
  ],
  "placements": [
    {
      "id": "51de…",           // placement id
      "copy_id": "9f0b…",      // the physical copy this placement owns
      "book_id": "c7a4…",      // resolved by the viewer through RBAC
      "x": 0.32, "y": 1.20,    // metres, bottom-left of the footprint
      "rotation": 0,           // 0 (spine up) or 90 (lying flat)
      "width_m": 0.021,        // resolved at publish time — see above
      "height_m": 0.203,
      "format": "b5soft"       // optional size preset key, for re-editing
    }
  ]
}
```

### Rules

- **Units are metres**, world coordinates, Y up — the same frame the app's
  editor works in, so nothing is converted on either side.
- **Ids are the app's.** A layout's id *is* its environment's UUID, so a device
  that published a room and a device that fetched it agree without a mapping
  table.
- **Unknown fields are ignored** by readers, and a reader that meets a
  `version` greater than it knows must refuse rather than guess — a partially
  understood room is a wrong room.
- **`kind`** says whether a segment is a shelf books rest on or furniture that
  only draws (plan 5 #29). It is written for every segment, including plain
  shelves: a document that omitted it would be read as all-shelves, and books
  would settle on a side panel. Absent in documents published before #29, where
  `shelf` is the behaviour they were written with — so this is an additive
  field, not a version bump.
- **The server does not interpret the doc.** It stores the JSON, checks it
  parses and is under the size cap, and hands it back. Any validation beyond
  that would be a second implementation of the format to keep in step.

### Size

Capped server-side at 512 KiB. A large room is a few hundred placements — well
under 100 KB — so the cap only ever catches a bug or an abuse, and a room that
genuinely exceeded it would be one nobody could see on a screen anyway.

## Sharing

A layout is shared with `share.scope = 'layout'`, `scope_id` = the layout id,
`viewer` only. `editor` is deliberately not offered: it would mean two people
dragging the same shelf, and the document model has no answer for that beyond
the 409 the publisher already sees.

Sharing a room does **not** share its books. The publish flow offers to do that
separately by creating a `Room: <name>` book group and a viewer share of it —
so book visibility rides the existing group RBAC rather than inventing a second
path to the same data, and revoking it is the ordinary share UI.
