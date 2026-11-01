import 'dart:io';
import 'package:flutter/material.dart';
import 'services/gui/linux_startup_probe.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_dashboard.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
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
