# Android app preview

## Direction

Continue the existing Flutter application and local conversion engine on Android.
The first usable preview should import files through Android's document picker,
run tools only after an explicit action, preserve originals, and let users export
or open their results. Keep the existing visual language and desktop behavior.

Reusing Flutter is preferred because the tool catalog, pure-Dart converters,
transactional executor, and Android PDF native binaries already exist. Compiling
the desktop UI unchanged is a smaller diagnostic milestone, but its paths and
file-opening behavior do not make a usable phone app. Rewriting in Kotlin would
duplicate the conversion workflows and is outside this milestone.

## Build foundation

Repair the incomplete Android runner with the installed Flutter SDK's supported
Gradle configuration, wrapper, launch activity, themes, and launcher resource.
Use application ID `com.converto.app`, the version from `pubspec.yaml`, and the
Flutter SDK's Android SDK defaults. Produce a developer-preview APK. Distribution
signing and Play Store publication are separate release work.

## Mobile integration

Keep converters independent of Flutter platform channels. Initialize app-private
data and result paths before starting the GUI and pass concrete paths into the
existing worker isolate. Preserve CLI environment overrides and desktop paths.
Use the system document picker for user-selected inputs; import readable copies
into private storage. Do not request broad storage access or network permission.

Provide explicit export through Android's create-document flow and opening
through content URIs with temporary read grants. A cancelled picker/export must
leave the current workspace and completed result intact. Report access/provider
failures in the interface. Do not advertise unimplemented incoming share intents.

At phone widths, stack header/navigation and workspace controls, keep primary
actions reachable, allow long file names and output paths to wrap, and handle
Android Back by returning from a workspace to the tool catalog. Avoid desktop
drag-and-drop and terminal instructions on Android. Keep large-screen layouts.

## Verification

Build the APK and inspect its manifest, native libraries, supported ABIs, and
signing status. Run analysis and the existing Flutter tests; add focused tests
only for mobile storage/channel behavior and phone-width regressions. Exercise
startup, import, conversion, export, cancellation, and result opening on an
Android device/emulator when available. Record device tests as pending when
there is no runtime, rather than equating an APK build with runtime verification.

Desktop-only optional executable helpers are unavailable on Android. Surface
their existing capability errors without claiming full desktop format parity.
No runtime downloads, telemetry, accounts, upload service, quotas, or artificial
file-size caps are introduced.
