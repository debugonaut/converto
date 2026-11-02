import 'dart:io';
import 'package:path/path.dart' as p;

/// Concrete mobile paths are initialized by the GUI, never by CLI converters.
class AppPaths {
  static String? _mobileData;
  static String? _mobileOutput;

  static void configureMobile({required String data, required String output}) {
    if (!p.isAbsolute(data) || !p.isAbsolute(output)) {
      throw ArgumentError('Mobile storage paths must be absolute.');
    }
    _mobileData = data;
    _mobileOutput = output;
  }

  static String dataDirectory(Map<String, String> environment) =>
      environment['CONVERTO_DATA_DIR'] ??
      _mobileData ??
      p.join(
        environment['HOME'] ?? environment['USERPROFILE'] ?? '.',
        '.converto',
      );

  static String? get mobileOutputDirectory => _mobileOutput;
  static String get localDataDirectory => dataDirectory(Platform.environment);
}
