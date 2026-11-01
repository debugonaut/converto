import 'package:flutter_test/flutter_test.dart';
import 'package:converto/core/terminal/interactive_shell.dart';

void main() {
  group('Cross-Platform Drag-and-Drop Parsing Tests', () {
    group('Windows Drag and Drop Formats', () {
      test('preserves backslashes in plain Windows paths', () {
        final tokens = InteractiveShell.tokenize(r'C:\Users\John\Documents\file.pdf');
        expect(tokens, [r'C:\Users\John\Documents\file.pdf']);
      });

      test('parses double-quoted Windows paths with spaces', () {
        final tokens =
            InteractiveShell.tokenize(r'"C:\Users\John Doe\Documents\file.pdf"');
        expect(tokens, [r'C:\Users\John Doe\Documents\file.pdf']);
      });

      test('normalizes trailing backslash on Windows directory paths', () {
        final tokensQuoted =
            InteractiveShell.tokenize(r'"C:\Users\John Doe\Documents\"');
        expect(tokensQuoted, [r'C:\Users\John Doe\Documents']);

        final tokensPlain =
            InteractiveShell.tokenize(r'C:\Users\John\Documents\');
        expect(tokensPlain, [r'C:\Users\John\Documents']);
      });

      test('preserves Windows root drive path', () {
        final tokens = InteractiveShell.tokenize(r'C:\');
        expect(tokens, [r'C:\']);
      });

      test('strips PowerShell call operator (&) with double quotes', () {
        final tokens =
            InteractiveShell.tokenize(r'& "C:\Users\John\file.pdf"');
        expect(tokens, [r'C:\Users\John\file.pdf']);
      });

      test('strips PowerShell call operator (&) with single quotes', () {
        final tokens =
            InteractiveShell.tokenize(r"& 'C:\Users\John\file.pdf'");
        expect(tokens, [r'C:\Users\John\file.pdf']);
      });

      test('strips PowerShell call operator (&) plain unquoted', () {
        final tokens =
            InteractiveShell.tokenize(r'& C:\Users\John\file.pdf');
        expect(tokens, [r'C:\Users\John\file.pdf']);
      });

      test('parses multiple Windows files dragged simultaneously (plain)', () {
        final tokens = InteractiveShell.tokenize(
            r'C:\Users\John\f1.pdf C:\Users\John\f2.pdf');
        expect(tokens, [r'C:\Users\John\f1.pdf', r'C:\Users\John\f2.pdf']);
      });

      test('parses multiple Windows files dragged simultaneously (quoted)', () {
        final tokens = InteractiveShell.tokenize(
            r'"C:\Users\John\file 1.pdf" "C:\Users\John\file 2.pdf"');
        expect(tokens,
            [r'C:\Users\John\file 1.pdf', r'C:\Users\John\file 2.pdf']);
      });

      test('parses Windows file with shorthand target format', () {
        final tokens =
            InteractiveShell.tokenize(r'"C:\Users\John\file.pdf" png');
        expect(tokens, [r'C:\Users\John\file.pdf', 'png']);
      });
    });

    group('macOS Drag and Drop Formats', () {
      test('unescapes backslash-escaped spaces (Finder Terminal.app format)', () {
        final tokens = InteractiveShell.tokenize(
            r'/Users/john/My\ Documents/file.pdf ');
        expect(tokens, ['/Users/john/My Documents/file.pdf']);
      });

      test('parses single-quoted paths with spaces (iTerm2 format)', () {
        final tokens = InteractiveShell.tokenize(
            "'/Users/john/My Documents/file.pdf' ");
        expect(tokens, ['/Users/john/My Documents/file.pdf']);
      });

      test('normalizes trailing slash on dropped macOS folders', () {
        final tokens =
            InteractiveShell.tokenize(r'/Users/john/My\ Folder/ ');
        expect(tokens, ['/Users/john/My Folder']);
      });

      test('preserves Unix root directory', () {
        final tokens = InteractiveShell.tokenize('/');
        expect(tokens, ['/']);
      });

      test('parses multiple macOS files dropped together', () {
        final tokens = InteractiveShell.tokenize(
            r'/Users/john/f\ 1.png /Users/john/f\ 2.png ');
        expect(tokens, ['/Users/john/f 1.png', '/Users/john/f 2.png']);
      });

      test('parses macOS file with shorthand target format', () {
        final tokens =
            InteractiveShell.tokenize(r'/Users/john/f\ 1.png webp');
        expect(tokens, ['/Users/john/f 1.png', 'webp']);
      });
    });

    group('Linux (Nautilus / Dolphin) Drag and Drop Formats', () {
      test('resolves file:// URI to standard filesystem path', () {
        final tokens =
            InteractiveShell.tokenize('file:///home/user/Documents/test.pdf');
        expect(tokens, ['/home/user/Documents/test.pdf']);
      });

      test('resolves and decodes URL-encoded file:// URI (%20 to space)', () {
        final tokens = InteractiveShell.tokenize(
            'file:///home/user/Documents/My%20Document.pdf');
        expect(tokens, ['/home/user/Documents/My Document.pdf']);
      });

      test('resolves file://localhost/... XDND variant', () {
        final tokens = InteractiveShell.tokenize(
            'file://localhost/home/user/Documents/test.pdf');
        expect(tokens, ['/home/user/Documents/test.pdf']);
      });

      test('handles newline-separated multi-file drops from Nautilus', () {
        final tokens = InteractiveShell.tokenize(
            'file:///home/user/f1.pdf\nfile:///home/user/f2.pdf');
        expect(tokens, ['/home/user/f1.pdf', '/home/user/f2.pdf']);
      });

      test('normalizes trailing slash on Linux folder URIs', () {
        final tokens =
            InteractiveShell.tokenize('file:///home/user/MyFolder/');
        expect(tokens, ['/home/user/MyFolder']);
      });

      test('parses Linux file URI with shorthand target format', () {
        final tokens =
            InteractiveShell.tokenize('file:///home/user/test.png pdf');
        expect(tokens, ['/home/user/test.png', 'pdf']);
      });
    });

    group('Bracketed Paste and Edge Cases', () {
      test('strips bracketed paste markers', () {
        final tokens = InteractiveShell.tokenize(
            '\x1B[200~"C:\\Users\\John\\file.pdf"\x1B[201~');
        expect(tokens, [r'C:\Users\John\file.pdf']);
      });

      test('strips legacy 00~/01~ bracketed paste fragments', () {
        final tokens =
            InteractiveShell.tokenize('00~/Users/john/file.pdf01~');
        expect(tokens, ['/Users/john/file.pdf']);
      });

      test('handles empty input gracefully', () {
        final tokens = InteractiveShell.tokenize('');
        expect(tokens, isEmpty);
      });

      test('handles single unmatched quotes without RangeError', () {
        final single = InteractiveShell.tokenize("'");
        expect(single, isEmpty);

        final doubleQ = InteractiveShell.tokenize('"');
        expect(doubleQ, isEmpty);
      });

      test('tokenizes slash commands with Windows paths', () {
        final tokens = InteractiveShell.tokenize(
            r'/convert "C:\Users\John\photo.png" webp');
        expect(tokens, ['/convert', r'C:\Users\John\photo.png', 'webp']);
      });

      test('tokenizes slash commands with macOS paths', () {
        final tokens = InteractiveShell.tokenize(
            r'/merge /Users/john/a.pdf /Users/john/b.pdf');
        expect(tokens, ['/merge', '/Users/john/a.pdf', '/Users/john/b.pdf']);
      });

      test('exact user command: /convert single quoted path', () {
        const input = "/convert '/Users/aadeshkhande/Documents/spidey.png'";
        final tokens = InteractiveShell.tokenize(input);
        expect(tokens, ['/convert', '/Users/aadeshkhande/Documents/spidey.png']);

        final firstToken = tokens.first;
        final commandArgs =
            input.substring(input.indexOf(firstToken) + firstToken.length).trim();
        final argTokens = InteractiveShell.tokenize(commandArgs);
        expect(argTokens.first, '/Users/aadeshkhande/Documents/spidey.png');
        expect(argTokens.first.startsWith("'"), isFalse);
      });
    });
  });
}

