#!/usr/bin/env python3
"""Package portable tar.gz and Debian desktop app; verify the extracted runtimes."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import tarfile
from linux_bundle import digest, files, manifest, validate, verify_archive
from package_cli import third_party_notices


def run(command, **kwargs):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=90, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command[0]} exited {result.returncode}: {result.stdout}\n{result.stderr}')
    return result.stdout + result.stderr


def probe(app, temporary):
    env = {k: v for k, v in os.environ.items() if k not in (
        'LD_LIBRARY_PATH', 'LD_PRELOAD', 'GTK_PATH', 'GTK_MODULES', 'GIO_EXTRA_MODULES',
        'FLUTTER_ROOT', 'DART_SDK')}
    env.update(PATH='/usr/bin:/bin', HOME=str(temporary / 'home'),
               XDG_CONFIG_HOME=str(temporary / 'config'), XDG_CACHE_HOME=str(temporary / 'cache'),
               XDG_DATA_HOME=str(temporary / 'data'),
               CONVERTO_DATA_DIR=str(temporary / 'profile'),
               CONVERTO_OUTPUT_DIR=str(temporary / 'outputs'), CONVERTO_HISTORY='off',
               LIBGL_ALWAYS_SOFTWARE='1', GDK_BACKEND='x11')
    Path(env['HOME']).mkdir(exist_ok=True)
    log = run(['xvfb-run', '-a', 'dbus-run-session', '--', str(app / 'converto'),
               '--converto-startup-probe'], cwd=temporary, env=env)
    if 'CONVERTO_LINUX_FIRST_FRAME_OK' not in log or 'CONVERTO_LINUX_PICKERS_OK' not in log or 'CONVERTO_LINUX_PROBE_FAILED' in log:
        raise RuntimeError(f'Native startup/picker probe did not complete: {log}')
    return log


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, default=Path('build/linux/x64/release/bundle'))
    parser.add_argument('--report', type=Path, default=Path('build/audit/linux-app/package.json'))
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise RuntimeError('Build and package the Linux x64 app on Linux x64')
    root = Path(__file__).resolve().parents[1]
    output = root / 'Converto-Linux-x64.tar.gz'
    deb = root / 'Converto-Linux-amd64.deb'
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='converto-linux-') as name:
        temporary = Path(name)
        app = temporary / 'Converto'
        shutil.copytree(args.app, app)
        shutil.copy2(root / 'LICENSE', app / 'LICENSE')
        (app / 'THIRD_PARTY_NOTICES.txt').write_text(third_party_notices(root), encoding='utf-8')
        (app / 'START_HERE.txt').write_text(
            'Converto for Linux x86_64 — developer preview\n\n'
            'Extract the entire archive and open converto inside the Converto folder.\n'
            'Keep lib/ and data/ beside it. No Flutter/Dart SDK, accounts, downloads,\n'
            'FUSE, zenity, kdialog, or administrator installation is needed.\n'
            'Requires a GTK 3 desktop, glibc 2.35+ and working OpenGL drivers.\n'
            'Baseline verified on Ubuntu 22.04; other distributions need testing.\n'
            'Use the .deb for application-menu integration on Debian-based systems.\n\n'
            'Processing is local and uses available RAM/disk; no artificial quotas.\n'
            'Optional Office formats and WebP encoding can need local helpers,\n'
            'which are never downloaded by the app. Originals are preserved.\n'
            'Choose names/output folder before Run. Ctrl+O adds files, Ctrl+F searches.\n'
            'Preferences/history use your user profile, not this app folder.\n'
            'Manual GNOME/KDE, X11/Wayland and file-manager drag/drop QA is pending.\n', encoding='utf-8')
        binaries = validate(app)
        dependencies = {}
        glibc = set()
        for relative in binaries:
            path = app / relative
            # libapp.so is a Flutter AOT container with no ordinary dynamic dependencies.
            listing = run(['ldd', str(path)])
            if 'not found' in listing:
                raise RuntimeError(f'Missing runtime dependency in {relative}: {listing}')
            dependencies[relative] = listing.strip().splitlines()
            symbols = run(['objdump', '-T', str(path)])
            glibc.update(re.findall(r'\bGLIBC_(\d+\.\d+(?:\.\d+)?)\b', symbols))
        maximum = max(glibc, key=lambda s: tuple(map(int, s.split('.'))))
        if tuple(map(int, maximum.split('.'))) > (2, 35):
            raise RuntimeError(f'Linux runtime exceeds Ubuntu 22.04 glibc baseline: {maximum}')
        with tarfile.open(output, 'w:gz', compresslevel=9) as archive:
            archive.add(app, arcname='Converto')
        extracted = temporary / 'portable with spaces 日本語'
        verify_archive(output, app, extracted)
        portable_log = probe(extracted / 'Converto', temporary)
        (args.report.parent / 'portable-startup.log').write_text(portable_log)
        stage = temporary / 'debian'
        payload = stage / 'opt/converto'
        shutil.copytree(app, payload)
        (stage / 'usr/bin').mkdir(parents=True)
        launcher = stage / 'usr/bin/converto'
        launcher.write_text('#!/bin/sh\nexec /opt/converto/converto "$@"\n')
        launcher.chmod(0o755)
        desktop = stage / 'usr/share/applications'
        desktop.mkdir(parents=True)
        shutil.copy2(root / 'linux/converto.desktop', desktop / 'com.debugonaut.converto.desktop')
        icon = stage / 'usr/share/icons/hicolor/256x256/apps'
        icon.mkdir(parents=True)
        shutil.copy2(root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png', icon / 'com.debugonaut.converto.png')
        control = stage / 'DEBIAN'
        control.mkdir()
        # Ask dpkg to derive versions for all linked system libraries, including
        # plugins/native assets. App-local Flutter/PDF libraries have no shlibs db.
        (temporary / 'debian').mkdir(exist_ok=True)
        shlib_root = temporary / 'shlibs'
        (shlib_root / 'debian').mkdir(parents=True)
        (shlib_root / 'debian/control').write_text(
            'Source: converto\nSection: utils\nPriority: optional\n'
            'Maintainer: Converto <noreply@converto.local>\n\n'
            'Package: converto\nArchitecture: amd64\nDescription: Private offline file tools\n')
        shared_dirs = sorted({str((app / name).parent) for name in binaries})
        derived = run(['dpkg-shlibdeps', '-O', '--ignore-missing-info',
                       *['-l' + directory for directory in shared_dirs],
                       *['-e' + str(app / name) for name in binaries]], cwd=shlib_root)
        match = re.search(r'^shlibs:Depends=(.+)$', derived, re.MULTILINE)
        if not match:
            raise RuntimeError('No Debian runtime dependencies were derived')
        depends = match.group(1)
        installed_kib = (sum(p.stat().st_size for p in files(stage)) + 1023) // 1024
        (control / 'control').write_text(
            'Package: converto\nVersion: 1.0.0-preview.1\nArchitecture: amd64\n'
            'Section: utils\nPriority: optional\nMaintainer: Converto <noreply@converto.local>\n'
            f'Installed-Size: {installed_kib}\nDepends: {depends}\n'
            'Description: Private offline file tools\n'
            ' Convert, organize and edit files locally without accounts or quotas.\n')
        run(['dpkg-deb', '--root-owner-group', '-Zxz', '-z9', '--build', str(stage), str(deb)])
        deb_extracted = temporary / 'deb-extracted'
        run(['dpkg-deb', '-x', str(deb), str(deb_extracted)])
        if manifest(payload) != manifest(deb_extracted / 'opt/converto'):
            raise RuntimeError('Debian payload content or permissions changed')
        deb_log = probe(deb_extracted / 'opt/converto', temporary)
        (args.report.parent / 'debian-startup.log').write_text(deb_log)
        report = {
            'sourceCommit': run(['git', 'rev-parse', 'HEAD'], cwd=root).strip(),
            'architecture': 'x86_64', 'baseline': 'Ubuntu 22.04',
            'maximumRequiredGlibc': maximum, 'debianDepends': depends,
            'bundleBytes': sum(p.stat().st_size for p in files(app)),
            'artifacts': [{'file': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in (output, deb)],
            'verifiedBinaryFiles': binaries, 'dependencies': dependencies,
            'tarContentsAndModes': 'pass', 'debianContentsAndModes': 'pass',
            'portableFirstFrameAndPickerCancellation': 'pass',
            'debianFirstFrameAndPickerCancellation': 'pass',
            'runtime': 'Relocated bundles, isolated profile, only system PATH, Xvfb software GL',
            'nativeDragDropManual': 'pending', 'waylandAndKdeManual': 'pending',
        }
        args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({k: v for k, v in report.items() if k != 'dependencies'}, indent=2))


if __name__ == '__main__':
    main()
