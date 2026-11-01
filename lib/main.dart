import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConvertoApp());
}

class ConvertoApp extends StatefulWidget {
  const ConvertoApp({super.key});

  @override
  State<ConvertoApp> createState() => _ConvertoAppState();
}

class _ConvertoAppState extends State<ConvertoApp> {
  bool _isDark = true;

  void _toggleTheme() {
    setState(() => _isDark = !_isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Converto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HomeDashboard(
        onToggleTheme: _toggleTheme,
        isDark: _isDark,
      ),
    );
  }
}
