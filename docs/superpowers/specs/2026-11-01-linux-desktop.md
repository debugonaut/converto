# Linux desktop distribution

Continue the approved Mac/Windows desktop workflow on Linux without visual changes.
Use the same Flutter GUI, offline engines, previews, names, transactional output
handling, bounded caches and intake safeguards. No accounts, telemetry, helper
downloads, quotas or artificial file-size caps are added.

Ship an x86_64 portable tar.gz and a Debian amd64 package. The tar preserves Unix
execute bits and requires no FUSE or installer. The Debian package adds an app-menu
entry and icon. Build on Ubuntu 22.04 and reject native code requiring glibc newer
than 2.35. Other distributions are not claimed as tested.

Replace Linux file_picker shell-helper discovery with a small GTK 3 method channel
for local multiple files and output folders. Preserve other platforms' picker
implementations. Cancel returns null; overlapping requests return a contextual
busy error. File intake still validates files after selection and does not run
operations automatically.

Verify native architecture, complete runtime, system dependencies, archive
content/modes, Debian payload, and first Flutter frame after relocating both
packages into folders separate from source/build. The first-frame probe drives
the real Dart/GTK channel and cancellation paths for both pickers, then closes
through GTK's normal lifecycle. Run the existing 32-case GUI engine audit on
Linux in addition to CLI/unit/terminal checks.

Publish only verified artifacts to existing localhost download links. Native
GNOME/KDE, X11/Wayland, GPU, file-manager drag/drop and chooser acceptance QA must
be identified as pending until a human desktop pass.
