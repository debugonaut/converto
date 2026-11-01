# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

HTML5, CSS3 (shadcn design system tokens), Vanilla JavaScript. Zero runtime dependencies, 100% client-side.

## Users

Developers, professionals, students, researchers, and privacy-conscious users handling confidential documents (financials, contracts, medical records, proprietary code/images) who need to convert, merge, split, crop, compress, or watermark files locally on their device without uploading them to cloud services.

## Product Purpose

A 100% offline, local-first file converter and editor that runs entirely on the user's hardware. Eliminates cloud upload delays, file size restrictions, subscription paywalls, and privacy risks associated with services like iLovePDF or Smallpdf.

## Positioning

Unlike cloud converters that transfer private files to remote servers, Converto executes all conversions inside the device sandbox with zero network requests. Complete air-gap capability.

## Operating Context

Works on local desktop (macOS, Windows, Linux) and mobile (Android, iOS). The web landing page serves as the distribution hub, providing client-side OS detection to direct visitors immediately to their platform installer, alongside full technical specifications.

## Capabilities and Constraints

- **Supported Formats**:
  - Images: JPG, JPEG, PNG, WEBP, BMP, GIF, TIFF, ICO (convert, rotate, crop, compress, multi-image to PDF).
  - Documents: DOCX, DOC, ODT, RTF, TXT to PDF; PDF to PNG, JPG, TXT, DOCX, XLSX, PPTX.
  - Spreadsheets: XLSX, XLS, CSV to PDF table or CSV.
  - Presentations: PPTX, PPT to PDF or slide images.  - **PDF Tools** (all local, no external binaries): merge, split by page count / ranges / maximum size, extract pages, reorder or delete pages, rotate, crop margins, compress (screen/ebook/print/lossless), watermark, page numbers, text redaction, password protect/unlock, PDF/A conversion, metadata inspection.
- **Constraints**:
  - Zero server-side processing; zero telemetry; zero external analytics.
  - No quotas, accounts, uploads, or file-size caps other than local disk space.
  - Self-contained bundle: the native PDF engine adds ~22 MB (32 MB total on macOS arm64); no Ghostscript, poppler, or LibreOffice install is needed for PDF work.
  - Open source under Apache 2.0 license.

## Brand Commitments

- **Tone**: Pragmatic, direct, technical, honest. No marketing jargon, no exaggerated adjectives, no glowing neon effects.
- **Aesthetic**: shadcn-inspired minimal zinc/slate palette, high contrast, clean typography, precise 1px borders, crisp SVG icons.

## Evidence on Hand

- Verified offline file processing engine in Dart/Flutter.
- Native desktop bridges (LibreOffice CLI, native renderers).
- Fully inspectable local file sandbox.

## Product Principles

1. **Air-Gapped by Default**: No conversion ever initiates a network connection.
2. **Precision Over Hype**: State supported formats, capabilities, and technical constraints plainly.
3. **Frictionless Distribution**: Single-click access to the exact platform binary matching the user's system.
4. **Transparent Open Source**: Inspectable code, Apache 2.0 license, community-funded via voluntary sponsorship.

