import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Local optional codecs. Never installs or downloads a helper at runtime.
class LocalProcess {
  static String? find(String executable) {
    final paths = [
      ...(Platform.environment['PATH'] ?? '').split(
        Platform.isWindows ? ';' : ':',
      ),
      // Finder launches do not inherit the user's interactive shell PATH.
      if (Platform.isMacOS) ...['/opt/homebrew/bin', '/usr/local/bin'],
    ];
    final extensions = Platform.isWindows
        ? [
            '',
            ...(Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT').split(';'),
          ]
        : [''];
    for (final directory in paths) {
      if (directory.isEmpty) continue;
      for (final ext in extensions) {
        final file = File(p.join(directory, '$executable$ext'));
        if (file.existsSync()) return file.absolute.path;
      }
    }
    return null;
  }

  static Future<void> run(String executable, List<String> arguments) async {
    final process = await Process.start(executable, arguments);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    // Configurable hang protection for an optional external engine, not a size cap.
    final seconds =
        int.tryParse(Platform.environment['CONVERTO_HELPER_TIMEOUT'] ?? '') ??
        120;
    final code = await process.exitCode.timeout(
      Duration(seconds: seconds > 0 ? seconds : 120),
      onTimeout: () {
        process.kill();
        throw TimeoutException(
          'Local helper timed out. Set CONVERTO_HELPER_TIMEOUT to allow more time.',
        );
      },
    );
    final messages = await Future.wait([out, err]);
    if (code != 0)
      throw ProcessException(executable, arguments, messages.join('\n'), code);
  }
}
