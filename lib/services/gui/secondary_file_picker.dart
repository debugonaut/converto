import 'dart:io';
import '../../core/utils/file_utils.dart';
import 'desktop_file_picker.dart';
import 'mobile_documents.dart';

class PickedLocalFile {
  final String path;
  final Future<void> Function()? _release;
  bool _released = false;
  PickedLocalFile(this.path, {Future<void> Function()? release})
    : _release = release;
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release?.call();
  }
}

/// Credentials/logos never enter the app's convertible-document intake.
class SecondaryFilePicker {
  static Future<PickedLocalFile?> pick(List<String> extensions) async {
    final mobile = MobileDocuments.enabled;
    final paths = await DesktopFilePicker.pickFiles(
      extensions: extensions,
      allowMultiple: false,
    );
    if (paths == null || paths.isEmpty) return null;
    Future<void> release(String path) async {
      if (mobile) await MobileDocuments.releaseImport(path);
    }

    if (paths.length != 1 ||
        !extensions.contains(FileUtils.getExtension(paths.single)) ||
        await FileSystemEntity.type(paths.single, followLinks: false) !=
            FileSystemEntityType.file) {
      for (final path in paths) {
        await release(path);
      }
      throw ArgumentError(
        'Choose one local ${extensions.map((e) => e.toUpperCase()).join(' or ')} file.',
      );
    }
    return PickedLocalFile(paths.single, release: () => release(paths.single));
  }
}
