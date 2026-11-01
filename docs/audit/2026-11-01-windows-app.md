# Windows portable desktop app

The Windows distribution is a complete GUI app ZIP, separate from the CLI
bundle. The existing offline conversion engines and shared GUI workspace remain
unchanged in purpose and layout. No runtime installer, helper download, account
or service is introduced.

## Implementation

- Restored the incomplete native runner using the installed Flutter Windows
  template, including plugin/native-asset/AOT/ICU installation rules.
- Named the executable/window Converto, carried over the Mac icon, and set
  1180×840 initial dimensions with a DPI-aware 780×600 minimum client area.
- Used Windows keyboard modifiers, system font, Explorer labels and user-profile
  preferences. macOS keeps Command shortcuts and its existing typography.
- Packaged the complete release directory plus application-local MSVC release
  CRT files, license/notices and extraction instructions. PDB/LIB/EXP build
  artifacts are excluded; conversion resources are retained unchanged.
- Added architecture/completeness/CRC/fingerprint checks after extraction.
  Packaged DLLs must load. A hidden startup probe must reach the first Flutter
  frame from a separate working directory, with only app/system folders on PATH.
- Extended CI with Windows GUI executor checks, a native release build,
  verified portable packaging and separate app/audit artifacts.

## Checks and evidence

Local: 130 Flutter regressions pass; static analysis reports no issues; all
18 Mac/Windows package integrity tests pass. Windows CI runs the same checks,
then the 32-case real-engine GUI audit, native compile and extracted startup
probe. Source tests cover missing PDF/CRT files, mixed architectures, changed
resources, truncated binaries and unsafe ZIP paths/case aliases.

Flutter’s Windows Dart snapshot uses ELF format; the validator checks its
64-bit x86 architecture separately from PE executables/DLLs. The initial native
build exposed this and a real-format fixture now covers it.

Windows' Python ZIP reader normalizes backslashes in member names. The initial
new archive fixture exposed that difference. Validation now checks the raw
member name and rejects transformations consistently on all platforms; hostile
fixtures preserve their original bytes for this regression.

[Flutter's Windows build documentation](https://docs.flutter.dev/platform-integration/windows/building)
requires distributing the complete release runtime; Microsoft's
[DLL redistribution guidance](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute?view=msvc-170)
describes application-local C++ runtime deployment. Packaging uses the installed
Visual Studio release redist directory, without runtime network downloads.

## Manual coverage boundary

CI's hidden startup probe verifies native app/Flutter initialization; it does
not interact with Explorer, a file picker, save folders or display scaling.
Those checks remain pending a real Windows desktop pass. The manual guide is
in `build/manual-testing/windows/GUIDE.md`, with pending results explicitly
recorded. The app is an unsigned Windows 10/11 x64 developer preview. Windows
ARM-native, installers and code signing are not claimed.

Office previews use bounded local excerpts or Open original; Mac Quick Look is
not available on Windows. Legacy Office conversion and WebP encoding retain
existing optional local-helper requirements. Large-file speed/memory claims
require representative real-world measurements beyond the small synthetic
acceptance fixtures.
