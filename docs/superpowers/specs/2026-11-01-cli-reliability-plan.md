# Approved implementation sequence

The written design was approved in chat on 2026-11-01. The referenced writing-plans skill is not installed; this file records the implementation and validation sequence directly.

1. Build a fresh baseline with `dart build cli`; run the existing tests and static analysis. Generate deterministic local fixtures and save independent operation/format/terminal results.
2. Isolate terminal tokenization and prompt state. Repair EOF, interruption, bracketed paste, multiline input, Unicode and shell-escaped filenames. Add parser and actual pseudo-terminal regressions.
3. Share conversion dispatch and mixed merge logic. Validate all inputs and output choices, preserve order, propagate batch failure, remove silent format fallbacks and disclose optional Office support.
4. Make writes transactional, honor directory and copy output requests, clean temporary results, bound typo scans and verify size/DPI/numeric options.
5. Run the same independent matrix on the repaired binary; add portable CLI build/test CI and remove stale-binary testing assumptions.
6. Produce the operation-by-operation report with before/after outcomes, timings, byte sizes, resource measurements and explicit platform/fidelity limitations. Preserve the web and terminal appearance.
