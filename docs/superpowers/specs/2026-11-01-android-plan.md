# Android implementation plan

The user approved the Android app preview scope on 2026-11-01.

1. Repair Android Gradle configuration, restore the wrapper and resources, and
   validate the native project's dependency configuration.
2. Implement a small Android document bridge: private storage paths, local file
   import, explicit export, and read-only content-URI result opening. Preserve
   file names/extensions and perform copying off the platform thread.
3. Initialize mobile paths before the GUI, keeping the CLI's pure-Dart imports
   and the worker's concrete output directory unchanged.
4. Adapt navigation, header, settings, workspace actions, and results for phone
   widths. Handle Back and prevent navigation from discarding a running job.
5. Test mobile path persistence, channel cancellation/errors, and phone layouts
   across tools. Run analysis and the full existing Flutter suite.
6. Build release APKs, inspect manifest/native assets/signature, and run an
   emulator smoke test if one can be provisioned. Record exact evidence and
   remaining physical-device checks in an Android audit.
