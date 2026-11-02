import 'package:converto/core/terminal/command_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('command catalog', () {
    test('every command is unique and has a group', () {
      final commands = convertoCommands.map((item) => item.command).toList();
      expect(commands.toSet().length, commands.length);
      expect(
        convertoCommands.every((item) => item.command.startsWith('/')),
        isTrue,
      );
      expect(convertoCommands.any((item) => item.command == '/help'), isTrue);
      expect(
        convertoCommands.any((item) => item.command == '/privacy'),
        isTrue,
      );
    });

    test('filters by prefix', () {
      expect(filterCommands('/pdf').map((item) => item.command), [
        '/pdf2img',
        '/pdf2text',
        '/pdf2html',
        '/pdf2office',
        '/pdfa',
      ]);
      expect(filterCommands('/priv').map((item) => item.command), ['/privacy']);
      expect(filterCommands('/').length, convertoCommands.length);
    });

    test('suggests the closest command for typos', () {
      expect(suggestCommand('/mergz'), '/merge');
      expect(suggestCommand('/conver'), '/convert');
      expect(suggestCommand('/pdf2imh'), '/pdf2img');
      expect(suggestCommand('/privac'), '/privacy');
      expect(suggestCommand('/zzzz'), isNull);
    });
  });
}
