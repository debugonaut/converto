import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app_paths.dart';

class AndroidDocuments {
  static const channel = MethodChannel('com.converto.app/documents');
  static bool get enabled =>
      debugDefaultTargetPlatformOverride == TargetPlatform.android ||
      Platform.isAndroid;

  static Future<void> initialize() async {
    final paths = await channel.invokeMapMethod<String, String>('storagePaths');
    final data = paths?['data'];
    final output = paths?['output'];
    if (data == null || output == null) {
      throw const FileSystemException('Android storage is unavailable.');
    }
    AppPaths.configureMobile(data: data, output: output);
  }

  static Future<List<String>?> pickFiles() =>
      channel.invokeListMethod<String>('pickFiles');

  /// False means that the user cancelled the system Save dialog.
  static Future<bool> exportFile(String path) async =>
      await channel.invokeMethod<bool>('exportFile', {'path': path}) ?? false;

  static Future<void> openFile(String path) =>
      channel.invokeMethod<void>('openFile', {'path': path});
}
