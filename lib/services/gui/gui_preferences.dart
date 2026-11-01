import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../storage_service.dart';

class GuiPreferences {
  String? outputDirectory;
  bool rememberHistory = true;
  File get _file => File(
    p.join(
      Platform.environment['CONVERTO_DATA_DIR'] ??
          p.join(Platform.environment['HOME'] ?? '.', '.converto'),
      'desktop_preferences.json',
    ),
  );
  Future<void> load() async {
    try {
      final data = jsonDecode(await _file.readAsString()) as Map;
      final directory = data['outputDirectory'];
      if (directory is String && await Directory(directory).exists())
        outputDirectory = directory;
      rememberHistory = data['rememberHistory'] != false;
    } catch (_) {
      /* First launch or missing preferences uses defaults. */
    }
  }

  Future<void> save() async {
    await StorageService.writeAtomically(
      _file,
      (file) => file.writeAsString(
        jsonEncode({
          'outputDirectory': outputDirectory,
          'rememberHistory': rememberHistory,
        }),
        flush: true,
      ),
    );
  }
}
