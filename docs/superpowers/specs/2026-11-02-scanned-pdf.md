# Create scanned PDF

Add a dedicated tool to the conversion catalog. Accept every registered format
the app can already convert to PDF, including PDFs, images, documents,
spreadsheets, and presentations. Existing optional local-helper requirements
continue to apply. Always produce one PDF in the selected file order, preserving
all source pages. Single-file names default to source_scanned; multiple files
share one scanned output name and the existing ordering controls.

Expose grayscale (default), color, and black-and-white modes, contrast from
50–300% (default 120%), brightness from -50–50% (default 0%), and a black/white
cutoff from 10–90% (default 60%). Export resolution offers 150, 200, or 300 DPI.
Apply settings consistently across every page. The source preview and expanded
viewer show the filter when a raster preview is available, and Show original
allows comparison. Source text/metadata previews remain available for formats
without a raster preview. Reset options restores scan defaults.

Use a shared pure-Dart pixel transform for preview and export, flattening alpha
onto white paper. Preview processing is debounced, coalesced, and bounded in
resolution; filter work runs outside the UI isolate. Export converts non-PDF
inputs through existing local engines, renders one page at a time, applies the
filter, and embeds that page without stretching or changing its displayed PDF
dimensions. Intermediate page PDFs keep decoded-image memory bounded. All work
stays in private temporary staging, with cancellation checkpoints between pages,
per-source errors, collision-safe final naming, and cleanup on failure/cancel.

The output is image-only, with no selectable/searchable text, and this is stated
in the workspace. This tool does not add OCR or a camera capture workflow.

Verify pixel behavior, transparency, settings validation, multiple source types,
page order/dimensions/rotation, a single published result, original-file safety,
failure and cancellation cleanup, actual worker execution, live preview parity,
reset/comparison controls, and desktop/phone layouts. Preserve the earlier
multiple-images-to-one-PDF conversion behavior.
