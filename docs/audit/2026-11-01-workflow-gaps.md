# File workflow audit — 2026-11-01

This audit compares Converto's existing 19 tools against published Smallpdf and
iLovePDF workflows and their public import screens. Post-import competitor
behavior is based on official documentation, not an authenticated hands-on run.
No files were transmitted to a competitor. Findings below are observations
about Converto's source plus inferences about usability, not a claim of full
feature parity with either product.

## Sources

- [Smallpdf Merge](https://smallpdf.com/merge-pdf): thumbnail review and file/page arrangement.
- [Smallpdf Organize](https://smallpdf.com/organize-pdf): page reorder, duplicate, remove and continued editing.
- [Smallpdf Edit](https://smallpdf.com/edit-pdf): visual editing and an explicit export stage.
- [iLovePDF user guide](https://www.ilovepdf.com/help/documentation): task-specific controls, page selection, password handling and results.
- [iLovePDF Crop](https://www.ilovepdf.com/blog/how-to-crop-a-pdf-online-and-trim-margins-easily): visible crop region and result review.

## Findings and acceptance criteria

| Priority | Gap in Converto | Acceptance criterion |
|---|---|---|
| P1 | Most selected files show only an icon/extension | Local PDF/image thumbnails and informative metadata; local text excerpts where supported |
| P1 | No readable PDF preview inside workspaces | Browse/zoom pages without opening another app; explicit encrypted/corrupt states |
| P1 | Output names cannot be chosen | Inline names before Run, per-input batch names and numbered multi-output names |
| P1 | Organize/extract require memorized page expressions | Visual pages, selection and reorder, with numeric alternatives |
| P1 | Merge ordering requires repeated arrow clicks | Drag reorder plus keyboard-accessible move controls |
| P1 | Image transforms are blind until output opens | Updated image preview and reset action |
| P1 | Crop margins have no visible reference | Source page with a visible kept/cropped area |
| P1 | Batch failures lack consistent input context | Name the failing input; state that transactional batch outputs were not saved |
| P2 | Success offers filenames without an in-app review | Preview completed files and Open/Reveal actions |
| P2 | Continuing requires returning to Finder | Use result in a compatible tool while retaining explicit Run |
| P2 | Compression has no before/after summary | Actual input/output byte counts and truthful savings |
| P2 | Validation largely arrives after Run | Inline name/page/dimension errors and disabled invalid actions |
| P2 | No quick reset for editing options | Reset options restores the current tool's defaults |
| P2 | Filename-only cards hide size/page metadata | Readable file size, extension and page counts without long-path overflow |

The workflow work keeps all local engines bundled, no accounts/limits or remote
fonts, bounded preview memory, no runtime downloads, and the established visual
style. Thumbnail rendering is a preview operation; processing/saving still
requires Run. Preview size/cache bounds do not impose file-size quotas.

## Independent capability differences

Existing-PDF text replacement/annotation/form design, remote signature requests,
cloud collaboration and AI features are separate capabilities, not missing
buttons to pretend are implemented. The audit does not label Converto as having
those features. New CLI-only work already present in the shared workspace is
outside this isolated GUI change and must be validated before integration.

## Implemented workflow repairs

All 14 workflow acceptance criteria above are implemented in the existing Mac UI.
Preview, naming, validation, file/page controls and result review are shared
widgets/services rather than separate implementations per tool. The merge
workspace uses its otherwise-empty options column for a readable source preview.
The image editor preserves the input format by default. Optional history-write
failures are reported as warnings after a successful save, never as rollback.

The organizer exposed a native engine defect: duplicated page references could
report the correct page count but fail full-document reading after per-page
rotation. Repeated pages are now imported as independent PDF objects within the
private job transaction, retaining vectors/text. The regression reads the
complete four-page output, rather than checking only metadata.

## Preview format coverage

| Inputs | Local preview behavior | Automated coverage |
|---|---|---|
| PDF | Requested page only, page count, zoom/navigation; password entry in expanded viewer | Multi-page rendering, bad/valid password, corrupt/retry; decrypted preview never cached |
| PNG, JPG, JPEG, WebP, BMP, GIF, TIFF, TIF, ICO | ImageIO on Mac; bounded Dart fallback | Real encoded fixtures for all nine extensions, GIF frame navigation, largest ICO, JPEG EXIF orientation |
| TXT, CSV | Bounded text excerpt, UTF-8 or BOM-detected UTF-16 | Real text, CSV and UTF-16 fixtures |
| DOCX, ODT, XLSX, PPTX | OS Quick Look first-page thumbnail where available; local XML excerpt fallback | DOCX/ODT paragraphs, XLSX shared strings, PPTX slide order/navigation |
| DOC, XLS, PPT, ODP, RTF | OS Quick Look where available; metadata/Open original fallback | Fallback state tested; native Quick Look availability is a Mac manual check |

Quick Look is supplied by macOS and may use system-managed thumbnail caching.
Converto writes no app-managed thumbnail cache or preview conversions. Its LRU
budget is 16 MiB including decoded pixel estimates; Flutter's decoded image
cache is capped at 24 MiB/64 entries. Source renders are serial and identical
in-flight requests are shared. Image edits are debounced and coalesced into one
active renderer. Source preview dimensions are bounded to 1600 pixels; editing
previews to 1200. The Dart fallback declines automatic full-decodes above 32 MiB
or 50 megapixels. These are automatic-preview resource bounds; they do not
restrict conversion or saving. Processing still depends on available RAM/disk
and the local format engine.

## Verification

- `flutter analyze --no-pub`: no issues.
- `dart tool/verify_cli.dart`: full CLI bundle build; **126/126** Flutter regressions pass.
- `dart run tool/audit_gui.dart`: **32/32** real-engine checks; every saving tool
  receives a custom output name. Checks include rollback, cancellation,
  collisions, full PDF text readability, output dimensions and original bytes.
- `node --test test/launcher_test.cjs`: OS/architecture routing passes.
- `python3 -m unittest discover -s test/tool -p test_macos_bundle.py`: **7/7**
  package-integrity regressions pass.
- `swiftc -frontend -parse macos/Runner/MainFlutterWindow.swift`: syntax passes;
  the native Xcode compile and CPU package verification run in GitHub Actions.
- `tool/render_workflow_test.dart`: real local files, three repeated drop events,
  custom merge name, worker save, result preview, page duplicate/rotation, image
  edit and PDF crop; renders at 1180×840 and 780×600. These are offscreen Flutter
  renders, not Finder/native-picker interaction tests.
- Widget coverage includes 200% text, compact layouts, crop gestures, stale
  preview responses, no render-on-rebuild, inline invalid-name blocking, page
  selection/actions/reset and compatible result continuation.

For isolated visual reproduction:

```sh
CONVERTO_DATA_DIR="$PWD/build/audit/workflow-render/state" \
CONVERTO_OUTPUT_DIR="$PWD/build/audit/workflow-render/output" \
CONVERTO_HISTORY=off flutter test --no-pub tool/render_workflow_test.dart
```

New native ImageIO/Quick Look callbacks and Finder behavior need a manual pass
in the packaged app. Native UI automation permission was unavailable; the user
requested build and automated checks. The previously confirmed Finder drop,
native picker, merge and source-preservation checks remain recorded separately.
The GUI is Mac-first; Windows/Linux CI covers the shared CLI/Flutter regressions,
not a claim that native GUIs for those platforms have been exercised.

## Per-operation execution sample

One local run on this Apple Silicon Mac, using a synthetic three-page PDF and a
60×40 PNG. These are smoke-test timings, not throughput claims or large-file
benchmarks. Every row passed; `info` deliberately creates no output.

| Operation | Time (ms) | Outputs | Output bytes |
|---|---:|---:|---:|

| convert | 25.4 | 1 | 1,151 |
| merge | 271.2 | 1 | 3,776 |
| split | 9.5 | 3 | 6,444 |
| compress | 5.7 | 1 | 2,897 |
| organize | 24.3 | 1 | 7,734 |
| editImage | 7.5 | 1 | 85 |
| watermark | 4.2 | 1 | 4,779 |
| protect | 5.3 | 1 | 3,641 |
| redact | 7.5 | 1 | 3,658 |
| pdfImages | 74.7 | 3 | 16,091 |
| pdfText | 2.8 | 1 | 62 |
| pdfOffice | 3.0 | 1 | 2,643 |
| extract | 3.7 | 1 | 2,535 |
| rotate | 3.2 | 1 | 2,930 |
| pageNumbers | 4.4 | 1 | 4,428 |
| crop | 4.4 | 1 | 3,005 |
| pdfa | 23.4 | 1 | 220,653 |
| unlock | 6.7 | 1 | 2,900 |
| info | 1.2 | 0 | 0 |

Machine-readable local results: `build/audit/gui/results.json`. Full format/CLI
audit reports and the manual kit remain separate from this focused workflow audit.
