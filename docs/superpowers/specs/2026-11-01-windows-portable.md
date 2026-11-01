# Portable Windows desktop app

Ship the established offline GUI as a Windows 10/11 x64 ZIP, preserving its
layout, processing engines and explicit Run workflow. Keep the CLI ZIP separate.
The localhost Windows download must serve the desktop app when the build is
verified; the Mac buttons continue to serve the verified Mac ZIPs.

The checked-in Windows project is incomplete. Restore the standard Flutter
runner and its CMake asset/plugin installation rules, set the window/icon/title
to Converto, use the same 1180×840 initial and 780×600 minimum client area, and
retain per-monitor DPI awareness. Use Ctrl+O/Ctrl+F, Windows profile preferences,
Explorer labels and the Windows system font. Existing local PDF/image previews
and bounded Office excerpts serve Windows; Quick Look remains Mac-specific.

Package the complete release directory, application-local release MSVC CRT,
native PDF DLL, Flutter/AOT/ICU assets and third-party notices. Exclude build-only
PDB/LIB/EXP files. Never download a runtime or helper at app startup. Packaging
must verify x64 PE files, required assets, ZIP CRC and full-file fingerprints
after extraction. Verify the extracted DLLs load and that the native runner
reaches its first Flutter frame from a separate working directory using a
hidden startup probe. No interactive native UI automation is claimed.

CI retains the existing three-OS CLI checks, adds the GUI executor audit on
Windows, builds the release GUI, verifies the ZIP and publishes separate app
and audit artifacts. Local and CI regressions cover Windows packaging omissions,
architecture mismatches, modified data and archive path/alias attacks. Real
Explorer drag/drop and native dialog interaction still need a Windows desktop
manual pass, with a small synthetic fixture kit and explicit result recording.
