import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/gui/desktop_file_picker.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_dashboard.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 64;
  runApp(const ConvertoApp());
  if (Platform.isLinux && arguments.contains('--converto-startup-probe')) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // The native probe cancels both dialogs through their real response path.
        final files = await DesktopFilePicker.pickFiles(extensions: ['pdf']);
        final folder = await DesktopFilePicker.pickDirectory();
        if (files != null || folder != null)
          throw StateError('Picker cancellation');
        stdout.writeln('CONVERTO_LINUX_PICKERS_OK');
      } catch (error) {
        stderr.writeln('CONVERTO_LINUX_PROBE_FAILED: $error');
      } finally {
        await const MethodChannel(
          'com.debugonaut.converto/files',
        ).invokeMethod<void>('finishProbe');
      }
    });
  }
}

class ConvertoApp extends StatelessWidget {
  const ConvertoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Converto',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: const HomeDashboard(),
  );
}
