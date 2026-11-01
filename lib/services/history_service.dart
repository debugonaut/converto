import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'storage_service.dart';

class HistoryItem {
  final String id;
  final String sourceName;
  final String sourcePath;
  final String sourceFormat;
  final String targetPath;
  final String targetFormat;
  final int fileSizeBytes;
  final DateTime timestamp;

  HistoryItem({
    required this.id,
    required this.sourceName,
    required this.sourcePath,
    required this.sourceFormat,
    required this.targetPath,
    required this.targetFormat,
    required this.fileSizeBytes,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceName': sourceName,
    'sourcePath': sourcePath,
    'sourceFormat': sourceFormat,
    'targetPath': targetPath,
    'targetFormat': targetFormat,
    'fileSizeBytes': fileSizeBytes,
    'timestamp': timestamp.toIso8601String(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    id: json['id'] as String,
    sourceName: json['sourceName'] as String,
    sourcePath: json['sourcePath'] as String,
    sourceFormat: json['sourceFormat'] as String,
    targetPath: json['targetPath'] as String,
    targetFormat: json['targetFormat'] as String,
    fileSizeBytes: json['fileSizeBytes'] as int,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  final List<HistoryItem> _history = [];
  bool _initialized = false;

  Future<File> _getHistoryFile() async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final baseDir = Directory(
      Platform.environment['CONVERTO_DATA_DIR'] ?? p.join(home, '.converto'),
    );
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
    return File(p.join(baseDir.path, 'conversion_history.json'));
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final file = await _getHistoryFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        _history.clear();
        for (final item in data) {
          _history.add(HistoryItem.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Ignore initial file read error
    }
    _initialized = true;
  }

  List<HistoryItem> getHistory() {
    return List.unmodifiable(_history.reversed);
  }

  Future<void> addRecord(HistoryItem item) async {
    if (Platform.environment['CONVERTO_HISTORY'] == 'off') return;
    await init();
    _history.add(item);
    if (_history.length > 1000) _history.removeRange(0, _history.length - 1000);
    await _save();
  }

  Future<void> deleteRecord(String id) async {
    await init();
    _history.removeWhere((item) => item.id == id);
    await _save();
  }

  Future<void> clearHistory() async {
    await init();
    _history.clear();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getHistoryFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final jsonStr = jsonEncode(_history.map((e) => e.toJson()).toList());
      await StorageService.writeAtomically(
        file,
        (temp) => temp.writeAsString(jsonStr, flush: true),
      );
    } catch (_) {
      // Ignore save errors
    }
  }
}
