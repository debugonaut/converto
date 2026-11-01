# Complete local file workflows

The user requested inline output renaming for every operation, file previews,
and a competitor-informed audit that closes workflow gaps proactively. Preserve
the approved charcoal/amber/teal visual identity, offline engines, explicit Run,
collision-safe output staging and CPU-specific distribution.

## Audit scope and evidence

Inspect public Smallpdf/iLovePDF tool pages and their official guidance. Compare
our 19 implemented tools across intake, preview, selection, manipulation,
validation, export naming, results and continuation. Public import UI was
inspected in the browser; findings about post-import competitors use their
published guides. No user files or test fixtures are sent to another service.
An arbitrary PDF text/annotation editor, cloud AI, account services and remote
sharing are not represented as existing Converto capabilities.

## Resulting experience

- Added files show a real local thumbnail where supported, size/type and PDF
  page count. PDFs and images open an in-app page/zoom viewer; text/Office
  previews are local excerpts/metadata with an explicit Open original action.
  macOS may supply an OS Quick Look first-page thumbnail for Office files;
  system-managed thumbnail caching remains under macOS control.
  Unsupported/encrypted/corrupt previews have clear states and do not prevent
  valid operations. Previews never convert/save input files or run helpers.
- Bounded, serial background rendering, deduplicated requests and an LRU memory
  cache keep preview work off the UI thread. No app-managed thumbnail disk cache, recursive
  file watching, render-on-build loops or unbounded page rendering.
- Every saving operation exposes an editable output name before Run. A merge
  has one name; independent batch inputs have per-file names; split/page
  exports use the chosen base plus stable numbered suffixes. Format extensions
  come from the actual encoder. Invalid/path/device names fail before work.
- File ordering is draggable with keyboard buttons retained. PDF page previews
  support browsing, selection, reorder/duplicate/delete and reset for the
  existing organize/extract/split flows. Numeric controls remain available.
- Image rotation/flip/crop/resize and PDF crop/rotation give visual feedback.
  Edits can be reset. Preview feedback is bounded and never mutates originals.
- Clear per-input errors, progress, output previews, compression size feedback,
  and Use result in another tool close the run/review/continue loop. Chaining
  still requires an explicit Run. Names in local history match final outputs.

## Implementation and verification

1. Add output naming validation and transactional publication to the executor.
2. Add isolated local preview rendering and a bounded cache/viewer.
3. Add reusable file cards/page selection controls/output controls and wire all
   workspaces to the shared components. Preserve lazy lists for large batches.
4. Test naming/path attacks/collisions, multiple page outputs, encrypted/corrupt
   previews, cache deduplication/eviction, stale responses, page manipulation,
   cancellation, result reuse and compact/large-text layouts.
5. Render actual Flutter screens, rerun native/CLI regression and all GUI
   executor operations, build/sign/verify the Mac app in CI, retain small CPU
   downloads, and document any remaining independent capability gaps honestly.
