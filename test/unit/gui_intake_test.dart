import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/core/constants/format_types.dart';
import 'package:converto/services/gui/file_intake.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('gui-intake-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test(
    'repeated OS drops preserve order and literal punctuation without execution',
    () async {
      final names = [
        '01 with spaces.png',
        "02 apostrophe's.pdf",
        '03 日本語.PNG',
        '04 & dollar\$.txt',
      ];
      final paths = names
          .map(
            (name) => (File(
              p.join(scratch.path, name),
            )..writeAsStringSync('fixture')).path,
          )
          .toList();
      final first = await FileIntake.collect(paths.reversed);
      final repeated = await FileIntake.collect([
        ...paths,
        ...paths,
      ], existing: first.paths);
      expect(repeated.paths, paths.reversed.toList());
      expect(scratch.listSync().length, names.length);
    },
  );
  test(
    'folder drops are shallow, stable and skip hidden files and symlinks',
    () async {
      final a = File(p.join(scratch.path, 'a.png'))..writeAsStringSync('a');
      final b = File(p.join(scratch.path, 'b.pdf'))..writeAsStringSync('b');
      File(p.join(scratch.path, '.hidden.png')).writeAsStringSync('hidden');
      File(p.join(scratch.path, 'no.exe')).writeAsStringSync('unsupported');
      final nested = Directory(p.join(scratch.path, 'nested'))..createSync();
      File(p.join(nested.path, 'c.pdf')).writeAsStringSync('nested');
      if (!Platform.isWindows)
        Link(p.join(scratch.path, 'loop')).createSync(scratch.path);
      final result = await FileIntake.collect([scratch.path, scratch.path]);
      expect(result.paths, [a.path, b.path]);
    },
  );
  test(
    'missing, unsupported and linked inputs report errors without looping',
    () async {
      final missing = p.join(scratch.path, 'missing.pdf');
      final unknown = File(p.join(scratch.path, 'data.xyz'))
        ..writeAsStringSync('x');
      final result = await FileIntake.collect([missing, unknown.path]);
      expect(result.paths, isEmpty);
      expect(result.issues.length, 2);
    },
  );
  test(
    'all file tools are real and category and mixed-file routing is honest',
    () {
      expect(ToolDefinition.tools.length, ToolId.values.length);
      expect(
        ToolDefinition.tools.map((tool) => tool.id).toSet(),
        ToolId.values.toSet(),
      );
      expect(ToolDefinition.byId(ToolId.merge).accepts('png'), isTrue);
      expect(ToolDefinition.byId(ToolId.merge).accepts('docx'), isFalse);
      expect(ToolDefinition.byId(ToolId.editImage).accepts('pdf'), isFalse);
      final scan = ToolDefinition.byId(ToolId.scanPdf);
      expect(FormatRegistry.allSupportedExtensions.every(scan.accepts), isTrue);
      expect(scan.accepts('exe'), isFalse);
      expect(scan.targets(['pdf', 'jpg', 'docx']), ['pdf']);
      expect(ToolDefinition.byId(ToolId.convert).targets(['png', 'docx']), [
        'pdf',
      ]);
      expect(
        ToolDefinition.byId(ToolId.convert).targets(['pdf', 'csv']),
        isEmpty,
      );
    },
  );
}
