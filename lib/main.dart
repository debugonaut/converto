import 'dart:io';
import 'package:flutter/material.dart';
import 'services/gui/linux_startup_probe.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_dashboard.dart';
import 'services/gui/mobile_documents.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await MobileDocuments.initialize();
    } catch (error) {
      runApp(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not prepare app storage.',
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 12),
                      Text('$error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => main(arguments),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 64;
  runApp(const ConvertoApp());
  if (Platform.isLinux && arguments.contains('--converto-startup-probe')) {
    WidgetsBinding.instance.addPostFrameCallback((_) => runLinuxStartupProbe());
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
