import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 64;
  runApp(const ConvertoApp());
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
