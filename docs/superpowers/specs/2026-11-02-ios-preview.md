# iOS and iPadOS preview foundation

Continue the shared Flutter application after shipping the 1.1.0 desktop update.
Use the generated iOS runner and current UIScene lifecycle, supporting iPhone
and iPad from iOS 15. Reuse the offline conversion engines and tool catalog.

Share the mobile document channel across Android and iOS. Initialize private
application-support data and private Documents results before the GUI starts.
On iOS, import user-selected Files into per-request cache folders, coordinating
reads and balancing access to security-scoped URLs. Preserve input extensions
and names, reject directories/symlinks, and copy off the platform thread.

Export is an explicit system save-copy flow. Opening uses a system preview or
installed viewer, restricted to the app's result/import roots. Cancellation must
leave the selection and private result intact. Exclude app-private work from
backup; originals are read only. Download local copies in Files before offline
use when a document provider stores a source remotely.

Use mobile output actions/navigation/settings on both platforms and iOS system
fonts. Keep desktop drag/drop and folder commands on desktop. The first preview
does not add camera capture, incoming share intents, OCR downloads, accounts,
or a cloud service. Office/helper limitations continue to apply on mobile.

Validate shared phone/tablet layouts and channel behavior, compile simulator and
unsigned device apps on a native Mac runner, and inspect version, native engines
and Info.plist. Developer signing is required before installing a device build
or distributing through TestFlight/App Store. Physical-device file-provider,
backgrounding, accessibility and performance checks remain separate milestones.

Implementation references: [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate),
[Apple document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller).
