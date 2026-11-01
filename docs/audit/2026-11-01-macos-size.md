# Mac download size audit — 2026-11-01

The original ZIP was **39.9 MiB to download**, with **95.3 MiB installed**.
It contained both Intel and Apple Silicon executable slices. The PDF engine
accounted for 46.3 MiB, Flutter for 28.7 MiB and app AOT code for 16.6 MiB,
across both CPU architectures. Images and UI assets were a small fraction.

| Package | ZIP download | Installed app | Download reduction |
|---|---:|---:|---:|
| Original universal | 39.9 MiB | 95.3 MiB | — |
| Apple Silicon (`arm64`) | **19.6 MiB** | **47.3 MiB** | **50.9%** |
| Intel (`x86_64`) | **21.3 MiB** | **50.9 MiB** | **46.6%** |

Measurements exclude symlink aliases. Raw byte counts and SHA-256 archive
hashes are in [size-results.json](2026-11-01-macos/size-results.json).

## Change

`tool/package_macos.py` now copies the universal release build into private
staging, selects the requested CPU in every Mach-O executable/framework,
and retains the matching native-assets map. The original build is untouched.
Every engine, format, font resource and tool remains bundled. No runtime
network fetch, codec download, account or feature gate was introduced.

Each ZIP uses maximum standard ZIP compression and preserves native framework
symlinks. Packages are separately uploaded as `macos-app-AppleSilicon` and
`macos-app-Intel`, with a separate small `macos-app-audit` artifact. A user
downloads only the package matching their Mac. GitHub's outer archive uses
store mode to avoid recompressing an already compressed ZIP.

The binaries were already stripped. Their symbol/link-edit tables were small;
additional symbol removal would produce little benefit and could break native
interfaces. No further symbol stripping was applied. No runtime speed or RAM
improvement is claimed from removing an unused CPU slice.

## Verification

The source app is the previously verified native build from commit `221318f`.
Both CPU packages were created, extracted with macOS `ditto`, and passed
`codesign --verify --deep --strict`. All six executable files in each package
contain only their intended architecture. Their executable **and data sections**
hash identically to the matching slices in the source app, preserving the
already tested app and local engines. Changed signing headers/signatures are
excluded from the comparison. The native manifest keeps the selected CPU's
original engine mappings. Seven independent Python regression tests cover
code/data hashes, universal/thin parity, tamper detection, wrong CPUs,
truncation and symlink aliases.

As before, these are ad-hoc signed developer previews, not notarized releases.
Native Finder/picker interaction remains pending at the user's request; Intel
code was packaged and verified structurally but not executed on an Intel Mac.

## Reproduce

```sh
flutter build macos --release
python3 -m unittest discover -s test/tool -p test_macos_bundle.py
python3 tool/package_macos.py
# Or package an already-built app without rebuilding Dart/Flutter:
python3 tool/package_macos.py --app /path/to/Converto.app --output-dir build/packages
```

The resulting ZIPs are `Converto-macOS-arm64.zip` and
`Converto-macOS-x86_64.zip`. Each contains `Converto.app` at its root.
The installed app includes Flutter and the complete local PDF engine;
further substantial reductions require changing/rebuilding those components,
with corresponding format and functionality validation.
