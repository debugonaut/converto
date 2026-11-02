import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/core/constants/app_version.dart';

void main() {
  test('native package, CLI and Node launcher versions agree', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(version, '$appVersion+$appBuildNumber');
    expect(
      (jsonDecode(File('package.json').readAsStringSync()) as Map)['version'],
      appVersion,
    );
  });
}
