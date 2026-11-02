# Multiple images to one PDF

The Convert files workspace previously published one PDF per selected image,
requiring a second merge operation to create a single document.

For two or more images converted to PDF, default to One combined PDF. Provide
a PDF output choice with Separate PDFs for independent conversion. Keep single
images, other target formats, mixed document batches, and image editing on their
existing paths. Use the same image eligibility rule in the workspace and worker.

Combined mode exposes one output name and the existing file ordering controls;
hide per-image names and ignore their validation until separate output is selected.
The PDF page order follows the file list, including any pages supplied by a
multi-frame source through the existing image converter.

Convert inputs sequentially inside private job staging, preserving the original
JPEG embedding path, per-input errors, and cancellation checkpoints. Merge staged
PDFs through the local engine, then publish only the final PDF using the existing
collision-safe naming transaction. Failed or cancelled jobs leave no published
outputs. Record one result in optional local history.

Verify the rendered PDF's page colors and count, unchanged source bytes, separate
output naming, mixed inputs, corrupt-input rollback, cancellation, actual worker
execution/history, and UI mode/naming/order at desktop and phone sizes. Render the
real Flutter workflow for visual inspection.
