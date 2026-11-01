import 'dart:io';
import '../../services/local_process.dart';

class PlatformCapabilities {
  final bool isAndroid;
  final bool isWindows;
  final bool isMacOS;
  final bool isLinux;
  final bool isIOS;

  final bool hasLibreOfficeCLI;
  final String? libreOfficePath;
  final bool hasImageMagick;
  final bool hasGhostscript;

  const PlatformCapabilities({
    required this.isAndroid,
    required this.isWindows,
    required this.isMacOS,
    required this.isLinux,
    required this.isIOS,
    required this.hasLibreOfficeCLI,
    this.libreOfficePath,
    required this.hasImageMagick,
    required this.hasGhostscript,
  });

  bool get supportsCliOfficeConversion => hasLibreOfficeCLI;
}

class PlatformDetector {
  static PlatformCapabilities? _cached;

  static Future<PlatformCapabilities> detect() async {
    if (_cached != null) return _cached!;

    final isAndroid = Platform.isAndroid;
    final isWindows = Platform.isWindows;
    final isMacOS = Platform.isMacOS;
    final isLinux = Platform.isLinux;
    final isIOS = Platform.isIOS;

    String? libreOfficePath;
    bool hasLibreOffice = false;
    bool hasImageMagick = false;
    bool hasGhostscript = false;

    // Detect desktop helper tools
    if (Platform.environment['CONVERTO_DISABLE_HELPERS'] == '1') {
      // Explicit self-contained mode for air-gapped deployments and validation.
    } else if (isWindows) {
      libreOfficePath = _findWindowsLibreOffice();
      hasLibreOffice = libreOfficePath != null;
      hasImageMagick = _checkExecutableOnPath('magick.exe');
      hasGhostscript = _checkExecutableOnPath('gswin64c.exe');
    } else if (isMacOS) {
      libreOfficePath = _findMacLibreOffice();
      hasLibreOffice = libreOfficePath != null;
      hasImageMagick = _checkExecutableOnPath('magick');
      hasGhostscript = _checkExecutableOnPath('gs');
    } else if (isLinux) {
      libreOfficePath = _findLinuxLibreOffice();
      hasLibreOffice = libreOfficePath != null;
      hasImageMagick = _checkExecutableOnPath('magick');
      hasGhostscript = _checkExecutableOnPath('gs');
    }

    _cached = PlatformCapabilities(
      isAndroid: isAndroid,
      isWindows: isWindows,
      isMacOS: isMacOS,
      isLinux: isLinux,
      isIOS: isIOS,
      hasLibreOfficeCLI: hasLibreOffice,
      libreOfficePath: libreOfficePath,
      hasImageMagick: hasImageMagick,
      hasGhostscript: hasGhostscript,
    );

    return _cached!;
  }

  static String? _findWindowsLibreOffice() {
    final possiblePaths = [
      r'C:\Program Files\LibreOffice\program\soffice.exe',
      r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
    ];
    for (final p in possiblePaths) {
      if (File(p).existsSync()) return p;
    }
    final executable = LocalProcess.find('soffice.exe');
    if (executable != null) return executable;
    return null;
  }

  static String? _findMacLibreOffice() {
    const defaultMacPath =
        '/Applications/LibreOffice.app/Contents/MacOS/soffice';
    if (File(defaultMacPath).existsSync()) return defaultMacPath;
    final executable = LocalProcess.find('soffice');
    if (executable != null) return executable;
    return null;
  }

  static String? _findLinuxLibreOffice() {
    const paths = [
      '/usr/bin/soffice',
      '/usr/local/bin/soffice',
      '/snap/bin/libreoffice',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return p;
    }
    final executable = LocalProcess.find('soffice');
    if (executable != null) return executable;
    return null;
  }

  static bool _checkExecutableOnPath(String executable) =>
      LocalProcess.find(executable) != null;
}
