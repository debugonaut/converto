# CLI reliability and offline conversion audit

Date: 2026-11-01 (Asia/Kolkata)

## Scope and acceptance criteria

Establish the CLI before any GUI work. Preserve the landing page, terminal appearance, ASCII logo, command names and existing usable workflows. Audit all 25 catalog commands (19 file operations plus six information/session commands), every advertised source/target pair, terminal drops and failure cases. Report executed results separately from source inspection and OS coverage that needs a real runner.

Runtime conversions must remain local, with no signups, quotas, telemetry or network-dependent services. No product file-size limit will be added; available memory, disk, native codec constraints and operating-system limits still apply. Setup dependencies and optional local Office helpers must be disclosed honestly. Test measurements are local audit artifacts, not product analytics.

## Approaches considered

1. Patch individual command handlers: smallest diff, but keeps two dispatch paths and repeated inconsistent drop, merge and output handling.
2. Share input normalization, conversion dispatch and merge/output primitives between the existing entry points (recommended). Repair the current terminal reader and keep presentation code intact. Moderate diff, focused regression coverage and fewer independent failure paths.
3. Rewrite the CLI in another stack: greater packaging and compatibility risk, without evidence that it is necessary.

## Proposed implementation

### Input and terminal lifecycle

Treat shell argv as already tokenized; parse raw interactive input exactly once. Retain quoted/escaped Unicode paths, Windows drive and UNC paths, local file URIs, and explicit batch order. Reject malformed/remote URI inputs and invalid paths visibly. Handle bracketed paste as one logical input, including multiline URI lists. EOF, Ctrl+C, Ctrl+D, CRLF and terminal mode restoration must terminate or return to one prompt without loops. Restore the prior terminal state in finally blocks. Test through pseudo terminals, not only token functions.

### Shared execution and truthful capabilities

Use one conversion dispatcher and one mixed PDF/image merge primitive for direct arguments and interactive commands. Validate all inputs before writing. Preserve PDF pages and image order regardless of which family is first; never silently skip a corrupt or unsupported input. Propagate batch failures to process exit status. Report actual output formats by file signature. Encode WebP correctly with an already available local capability or explicitly fail if no supported encoder is installed; never write PNG under a WebP extension. Disclose legacy Office helper requirements and lossy text-only fallback fidelity. Render presentation image targets as real images. Keep aliases and discovery consistent with actual converter support.

### Storage, efficiency and local privacy

Use unique defaults and temporary files beside the destination, validate output/source conflicts and replace results only after successful conversion. Honor explicit output directories and same-format copy requests. Clean intermediate files on both success and failure. Keep batch processing sequential to bound peak resource use. Avoid unbounded whole-tree typo scans and rendering on every pasted byte. Do not persist passwords or add telemetry. Review history growth and local path retention. Optimize measured bottlenecks without inventing speed claims.

### Validation and shipping

Build a fresh CLI from the current source before integration tests; never silently use a stale architecture-specific binary. Generate deterministic fixtures with independently readable outputs: images, documents, spreadsheets, presentations and PDFs with known text/page counts. Validate signatures, page counts, selected text, dimensions, ordering, redaction, encryption, failure exit codes, cleanup and timeouts. Exercise quoted/escaped paths, punctuation, Unicode, URI lists, mixed/repeated files, folders, corruption, missing inputs, invalid options, output collisions and EOF.

Provide a repeatable CLI build/test path and CI matrix for macOS, Windows and Linux. This host is macOS arm64: Windows/Linux syntax tests do not count as native OS execution. Do not claim a release is verified until those native jobs run. Record time, input/output bytes and resource measurements with environment and fixture limits. Native codec defects and unavailable validators must remain explicit release blockers.

## Audit work checklist

- [x] Explore repository, requirements and baseline tests.
- [x] Compare scoped approaches and present this design.
- [x] User approval of this written design before production implementation.
- [x] Reproduce terminal/input and format defects against fresh source.
- [x] Implement focused repairs and independent regression checks.
- [x] Execute operation/format/edge matrix and platform checks available here.
- [x] Deliver machine-readable results and a detailed findings/release report.

No Git metadata is present in this workspace; the design cannot be committed here without creating a new repository, which is outside this task.
