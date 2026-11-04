import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app_paths.dart';

class MobileDocuments {
  static const channel = MethodChannel('com.converto.app/documents');
  static bool get enabled {
    final override = debugDefaultTargetPlatformOverride;
    if (override != null)
      return override == TargetPlatform.android ||
          override == TargetPlatform.iOS;
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<void> initialize() async {
    final paths = await channel.invokeMapMethod<String, String>('storagePaths');
    final data = paths?['data'];
    final output = paths?['output'];
    if (data == null || output == null) {
      throw const FileSystemException('App storage is unavailable.');
    }
    AppPaths.configureMobile(data: data, output: output);
  }

  static Future<List<String>?> pickFiles({
    List<String> extensions = const [],
    bool allowMultiple = true,
  }) => channel.invokeListMethod<String>('pickFiles', {
    'extensions': extensions,
    'allowMultiple': allowMultiple,
  });

  static Future<void> releaseImport(String path) =>
      channel.invokeMethod<void>('releaseImport', {'path': path});

  /// False means that the user cancelled the system Save dialog.
  static Future<bool> exportFile(String path) async =>
      await channel.invokeMethod<bool>('exportFile', {'path': path}) ?? false;

  static Future<void> openFile(String path) =>
      channel.invokeMethod<void>('openFile', {'path': path});
}
