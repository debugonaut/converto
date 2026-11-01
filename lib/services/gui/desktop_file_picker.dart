import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// GTK is already required by Flutter; no zenity/kdialog process is needed.
class DesktopFilePicker {
  static const channel = MethodChannel('com.debugonaut.converto/files');

  static Future<List<String>?> pickFiles({
    required List<String> extensions,
  }) async {
    if (Platform.isLinux) {
      return channel.invokeListMethod<String>('pickFiles', {
        'extensions': extensions,
      });
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: extensions,
      dialogTitle: 'Choose files to work with',
    );
    return result?.paths.whereType<String>().toList();
  }

  static Future<String?> pickDirectory() {
    if (Platform.isLinux) return channel.invokeMethod<String>('pickDirectory');
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Save results to');
  }
}
