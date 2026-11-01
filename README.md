# Converto CLI

Convert and edit files locally. No accounts, quotas, telemetry, uploads or cloud processing. The CLI is the shipping focus; the existing landing page and terminal artwork are preserved.

```sh
converto
converto convert photo.jpg --to pdf --output photo.pdf
converto merge first.pdf photo.png last.pdf --output combined.pdf
converto pdf2img report.pdf --to png --dpi 150 --output pages/
converto split report.pdf --every 10 --output parts/
converto help
```

Inside the terminal, type `/` for the existing 25-command menu. Drop quoted or shell-escaped paths, local `file://` URIs, multiple files, or a folder. Folder scans are shallow and sorted; hidden files, unsupported extensions and symlinks are skipped. PDF/image groups merge in input order. Other groups convert sequentially, with a nonzero exit status if any file fails. Single-file conversions to an image export the first PDF page/slide; `pdf2img` exports every PDF page.

The self-contained core supports JPEG/JPG, PNG, BMP, GIF, TIFF/TIF, ICO, WebP decoding, PDF tools and PDF-to-Office, TXT, DOCX text/tables, XLSX/CSV tables, ODT text extraction, and PPTX text fallback. Animated GIF and multipage TIFF inputs retain every frame/page when converted to PDF. XLSX-to-PDF includes every sheet. CSV export uses the first worksheet and reports this when more than one exists.

Optional **installed local helpers**, never downloaded by the CLI at runtime:

| Capability | Local requirement |
|---|---|
| WebP encoding | `cwebp` |
| DOC, XLS, PPT and ODP conversion | LibreOffice (`soffice`) |
| RTF conversion; ODT to PDF | LibreOffice |
| Text beyond the built-in Western font | LibreOffice and suitable installed fonts |
| Original DOCX/PPTX layout and graphics | LibreOffice; otherwise a disclosed text-oriented fallback |

UTF-8 and BOM-marked UTF-16 LE/BE text and CSV inputs are supported. Same-format text copies retain their original bytes. Missing helpers produce an explicit error; unsupported font content is rejected rather than silently dropping characters. WebP output is always genuine WebP, never renamed PNG. Optional helper processes use private temporary directories/profiles and a configurable timeout (`CONVERTO_HELPER_TIMEOUT`, seconds, default 120).

There is no application file-size cap. Available RAM/disk, codecs and the operating system still limit what can be processed. Several parsers decode whole files in memory. Layout fidelity, fonts, charts, macros and formula recalculation vary by engine; the fallback parsers are not substitutes for an Office renderer. PDF/A output still needs independent conformance validation before archival use. Text redaction removes matching text spans and can remove adjacent words in that span. Originals are kept by default.

Outputs default to `~/Documents/Converto/` (or the current directory when Documents is unavailable). Explicit output directories are supported. Existing destinations are replaced only after their new file is written successfully. Default filenames avoid existing files in sequential runs. Simultaneous processes targeting the same default basename are not yet coordinated; use separate output paths for those runs.

Local history records filenames and paths, never passwords. It is capped at 1,000 entries. Configuration:

| Environment variable | Meaning |
|---|---|
| `CONVERTO_OUTPUT_DIR` | Default output directory |
| `CONVERTO_DATA_DIR` | History directory, default `~/.converto` |
| `CONVERTO_HISTORY=off` | Disable new history records |
| `CONVERTO_DISABLE_HELPERS=1` | Restrict conversion to the self-contained core |
| `CONVERTO_HELPER_TIMEOUT` | Allow more time for large Office/codec jobs |

For OS-enforced network isolation, block the CLI and any helper children. The complete macOS audit was executed with networking denied, including the optional helpers. This proves the tested cases work offline; it is not a claim that every third-party helper version never attempts a connection.

Build and verify from source with an installed Flutter SDK:

```sh
flutter pub get
flutter analyze --no-pub
dart tool/verify_cli.dart
node --test test/launcher_test.cjs
python3 -m pip install -r tool/audit-requirements.txt
python3 tool/audit_cli.py --binary build/cli/macos_arm64/bundle/bin/converto --output build/audit/my-run
python3 tool/test_terminal.py --binary build/cli/macos_arm64/bundle/bin/converto --output build/audit/my-terminal-run
```

Dependency installation is a build/setup step; running a completed native bundle needs no Dart, Flutter, Node or Python. Ship the entire `bundle/` directory, including `lib/`. The npm launcher only starts an exact matching OS/architecture bundle and never downloads one. `npm run test:cli` always builds current source before testing it.

CI builds native CLI bundles on macOS, Windows and Linux. Native Windows console/ConPTY drag-and-drop verification and Linux desktop-terminal checks remain release gates until actually executed. See `docs/audit/2026-11-01-cli-audit.md` for measured results and remaining limitations.
