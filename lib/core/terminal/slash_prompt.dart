import 'dart:convert';
import 'dart:io';
import 'command_catalog.dart';
import 'terminal_ui.dart';
import 'terminal_input.dart';

class SlashPrompt {
  static void pushBack(int byte) => TerminalInput.pushBack(byte);
  static Future<int> readByte() => TerminalInput.readByte();
  static Future<String?> readPlainLine() => TerminalInput.readLine();

  /// Reads a single line interactively with real-time popup dropdown when '/' is pressed
  static Future<String?> readLine({String promptLabel = 'converto › '}) async {
    if (!stdin.hasTerminal ||
        !stdout.hasTerminal ||
        !stdout.supportsAnsiEscapes) {
      // Non-interactive fallback (e.g. pipes, scripts, CI)
      stdout.write(promptLabel);
      return TerminalInput.readLine();
    }

    // Enter raw mode for immediate keystroke capture
    final previousLineMode = stdin.lineMode;
    final previousEchoMode = stdin.echoMode;

    String buffer = '';
    int selectedIndex = 0;
    int previousDropdownLines = 0;
    bool dropdownDismissed = false;

    void clearDropdown() {
      if (previousDropdownLines > 0) {
        // Save current cursor position
        stdout.write('\x1B[s');
        for (int i = 0; i < previousDropdownLines; i++) {
          stdout.write('\n\x1B[2K'); // move down and clear line
        }
        // Restore cursor position
        stdout.write('\x1B[u');
        previousDropdownLines = 0;
      }
    }

    String itemLine(
      SlashCommandItem item,
      bool isSelected, {
      required int commandWidth,
      required int argsWidth,
      required int descWidth,
    }) {
      final prefix = isSelected
          ? TerminalUI.style(' ❯ ', TerminalUI.brightCyan + TerminalUI.bold)
          : '   ';
      final command = TerminalUI.style(
        item.command.padRight(commandWidth),
        isSelected
            ? TerminalUI.brightAmber + TerminalUI.bold
            : TerminalUI.amber,
      );
      final args = TerminalUI.style(
        item.args.padRight(argsWidth),
        TerminalUI.gray,
      );
      final desc = TerminalUI.style(
        TerminalUI.fit(item.desc, descWidth),
        isSelected ? TerminalUI.bold : TerminalUI.dim,
      );
      return '$prefix$command$args$desc';
    }

    void render() {
      // Return to line start and clear line
      stdout.write('\r\x1B[2K');
      stdout.write(
        '${TerminalUI.style("converto", TerminalUI.cyan + TerminalUI.bold)} ${TerminalUI.style("›", TerminalUI.amber)} ${buffer.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')}',
      );

      clearDropdown();

      // Check if user is typing a slash command (not an absolute path or quoted path)
      if (dropdownDismissed ||
          !buffer.startsWith('/') ||
          buffer.contains(' ') ||
          buffer.indexOf('/', 1) != -1 ||
          buffer.contains('.') ||
          buffer.startsWith('/Users') ||
          buffer.startsWith('/home') ||
          buffer.startsWith('/var') ||
          buffer.startsWith('/tmp') ||
          buffer.startsWith('/Volumes') ||
          buffer.startsWith('/private') ||
          buffer.startsWith('/opt') ||
          buffer.startsWith('/usr') ||
          buffer.startsWith('/etc') ||
          buffer.startsWith('/Applications')) {
        return;
      }

      final matches = filterCommands(buffer);
      if (matches.isEmpty) return;

      if (selectedIndex >= matches.length) {
        selectedIndex = matches.length - 1;
      }
      if (selectedIndex < 0) selectedIndex = 0;

      final boxWidth = TerminalUI.menuWidth;
      final contentWidth = boxWidth - 3;
      const commandWidth = 15;
      const argsWidth = 20;
      final descWidth = (contentWidth - 3 - commandWidth - argsWidth).clamp(
        10,
        100,
      );

      // Category headers are useful when browsing the whole menu, but noisy
      // while filtering. Show them only for the bare "/" view.
      final grouped = buffer == '/';
      final body = <String>[];
      final itemLineIndex = <int>[];
      if (grouped) {
        CommandGroup? activeGroup;
        for (int i = 0; i < matches.length; i++) {
          final item = matches[i];
          if (item.group != activeGroup) {
            body.add(TerminalUI.groupHeader(item.group, contentWidth));
            activeGroup = item.group;
          }
          itemLineIndex.add(body.length);
          body.add(
            itemLine(
              item,
              i == selectedIndex,
              commandWidth: commandWidth,
              argsWidth: argsWidth,
              descWidth: descWidth,
            ),
          );
        }
      } else {
        for (int i = 0; i < matches.length; i++) {
          itemLineIndex.add(body.length);
          body.add(
            itemLine(
              matches[i],
              i == selectedIndex,
              commandWidth: commandWidth,
              argsWidth: argsWidth,
              descWidth: descWidth,
            ),
          );
        }
      }

      // Keep the dropdown inside the terminal. Long menus scroll around the
      // selected tool instead of pushing the prompt off screen.
      var maxBody = 14;
      try {
        if (stdout.hasTerminal) {
          maxBody = (stdout.terminalLines - 9).clamp(8, 22);
        }
      } catch (_) {}

      var start = 0;
      if (body.length > maxBody) {
        final selectedLine = itemLineIndex[selectedIndex];
        start = (selectedLine - maxBody ~/ 2).clamp(0, body.length - maxBody);
      }
      final visibleBody = body.sublist(
        start,
        (start + maxBody).clamp(0, body.length),
      );

      // Save cursor at end of input line
      stdout.write('\x1B[s');

      final shownFrom = start + 1;
      final shownTo = start + visibleBody.length;
      final range = body.length > visibleBody.length
          ? ' $shownFrom-$shownTo/${body.length} '
          : '';
      final title = ' Tools$range (↑/↓ · Tab · Esc) ';
      final topBorder =
          '╭─$title${'─' * (boxWidth - title.length - 3).clamp(0, 500)}╮';

      stdout.write('\n\x1B[2K${TerminalUI.style(topBorder, TerminalUI.amber)}');
      previousDropdownLines =
          visibleBody.length + 2; // top border + body + bottom

      for (final line in visibleBody) {
        stdout.write(
          '\n\x1B[2K${TerminalUI.style('│', TerminalUI.amber)} '
          '${TerminalUI.padVisible(line, contentWidth)}'
          '${TerminalUI.style('│', TerminalUI.amber)}',
        );
      }

      stdout.write(
        '\n\x1B[2K${TerminalUI.style('╰${'─' * (boxWidth - 2)}╯', TerminalUI.amber)}',
      );

      // Restore cursor to input line
      stdout.write('\x1B[u');
    }

    try {
      stdin.lineMode = false;
      stdin.echoMode = false;
      stdout.write('\x1b[?2004h');
      render();

      var escPending = false;
      var csiPending = false;
      final csiBuffer = StringBuffer();
      bool inBracketedPaste = false;
      final pasteBytes = <int>[];
      int pasteClosingMatch = 0; // tracks matching against \x1B[201~
      final utf8Buffer = <int>[];

      while (true) {
        final byte = await readByte();
        if (byte == -1) break;

        // Ctrl+C (Interrupt) always exits immediately
        if (byte == 3) {
          clearDropdown();
          stdout.writeln();
          exitCode = 130;
          return null;
        }

        // Raw terminals deliver Ctrl+D as a byte, not a stream EOF.
        if (byte == 4) return buffer.isEmpty ? null : buffer;

        // --- BRACKETED PASTE MODE ---
        if (inBracketedPaste) {
          // Look for closing sequence: \x1B [ 2 0 1 ~
          if (byte == 27) {
            pasteClosingMatch = 1;
            continue;
          }
          if (pasteClosingMatch == 1 && byte == 91) {
            pasteClosingMatch = 2;
            continue;
          }
          if (pasteClosingMatch == 2 && byte == 50) {
            pasteClosingMatch = 3;
            continue;
          }
          if (pasteClosingMatch == 3 && byte == 48) {
            pasteClosingMatch = 4;
            continue;
          }
          if (pasteClosingMatch == 4 && byte == 49) {
            pasteClosingMatch = 5;
            continue;
          }
          if (pasteClosingMatch == 5 && byte == 126) {
            inBracketedPaste = false;
            pasteClosingMatch = 0;
            if (pasteBytes.isNotEmpty) {
              buffer += utf8.decode(pasteBytes, allowMalformed: true);
              pasteBytes.clear();
              selectedIndex = 0;
              dropdownDismissed = false;
              render();
            }
            continue;
          }

          // If a partial match failed, flush the matched prefix bytes into pasteBytes
          if (pasteClosingMatch > 0) {
            const prefixBytes = [27, 91, 50, 48, 49]; // \x1B [ 2 0 1
            for (int k = 0; k < pasteClosingMatch; k++) {
              pasteBytes.add(prefixBytes[k]);
            }
            pasteClosingMatch = 0;
          }

          pasteBytes.add(byte);
          continue;
        }

        // --- ESCAPE SEQUENCE HANDLING ---
        if (escPending) {
          escPending = false;
          if (byte == 91) {
            // CSI (\x1B[)
            csiPending = true;
            csiBuffer.clear();
            continue;
          }
          // A bare Escape dismisses the dropdown
          if (buffer == '/') buffer = '';
          dropdownDismissed = true;
          clearDropdown();
          render();
          // Process the following printable key instead of losing it.
        }

        if (csiPending && (byte == 10 || byte == 13)) csiPending = false;

        if (csiPending) {
          // CSI parameter/intermediate bytes are 0x20..0x3F (digits, semicolons)
          // Final bytes are 0x40..0x7E (letters, tilde ~)
          csiBuffer.writeCharCode(byte);
          final seq = csiBuffer.toString();

          // Check for bracketed paste start: \x1B[200~
          if (seq == '200~') {
            csiPending = false;
            inBracketedPaste = true;
            pasteBytes.clear();
            pasteClosingMatch = 0;
            continue;
          }

          // Arrow keys
          if (seq == 'A' || seq == 'B') {
            csiPending = false;
            final isSlashCmd =
                buffer.startsWith('/') &&
                !buffer.contains(' ') &&
                buffer.indexOf('/', 1) == -1;
            final matches = isSlashCmd
                ? filterCommands(buffer)
                : <SlashCommandItem>[];

            if (matches.isNotEmpty) {
              dropdownDismissed = false;
              if (seq == 'A') {
                selectedIndex =
                    (selectedIndex - 1 + matches.length) % matches.length;
              } else {
                selectedIndex = (selectedIndex + 1) % matches.length;
              }
              render();
            }
            continue;
          }

          // Any final byte terminates the CSI sequence (prevents hanging on Insert \x1B[2~ or other keys)
          if ((byte >= 0x40 && byte <= 0x7E) || csiBuffer.length > 16) {
            csiPending = false;
            continue;
          }
          continue;
        }

        // Enter key (CR or LF)
        if (byte == 10 || byte == 13) {
          final isSlashCmd =
              !dropdownDismissed &&
              buffer.startsWith('/') &&
              !buffer.contains(' ') &&
              buffer.indexOf('/', 1) == -1;
          final matches = isSlashCmd
              ? filterCommands(buffer)
              : <SlashCommandItem>[];

          if (isSlashCmd && matches.isNotEmpty) {
            if (selectedIndex >= matches.length) {
              selectedIndex = matches.length - 1;
            }
            final selected = matches[selectedIndex];
            clearDropdown();

            if (selected.requiresArgs) {
              buffer = '${selected.command} ';
              selectedIndex = 0;
              render();
              continue;
            } else {
              buffer = selected.command;
              stdout.writeln();
              return buffer;
            }
          }

          clearDropdown();
          stdout.writeln();
          return buffer;
        }

        // Tab key
        if (byte == 9) {
          final isSlashCmd = buffer.startsWith('/') && !buffer.contains(' ');
          final matches = isSlashCmd
              ? filterCommands(buffer)
              : <SlashCommandItem>[];

          if (isSlashCmd && matches.isNotEmpty) {
            if (selectedIndex >= matches.length) {
              selectedIndex = matches.length - 1;
            }
            final selected = matches[selectedIndex];
            clearDropdown();
            buffer = selected.requiresArgs
                ? '${selected.command} '
                : selected.command;
            selectedIndex = 0;
            dropdownDismissed = false;
            render();
            continue;
          }
        }

        // Backspace key (127 on Mac/Linux, 8 on Windows)
        if (byte == 127 || byte == 8) {
          if (buffer.isNotEmpty) {
            final runes = buffer.runes.toList();
            buffer = String.fromCharCodes(runes.take(runes.length - 1));
            selectedIndex = 0;
            dropdownDismissed = false;
            render();
          }
          continue;
        }

        // Bare Escape key
        if (byte == 27) {
          escPending = true;
          continue;
        }

        // UTF-8 / printable character handling
        if (byte >= 32) {
          if (byte < 128) {
            // Standard ASCII character
            buffer += String.fromCharCode(byte);
            selectedIndex = 0;
            dropdownDismissed = false;
            render();
          } else {
            // Multibyte UTF-8 byte
            utf8Buffer.add(byte);
            try {
              final decodedChar = utf8.decode(utf8Buffer);
              buffer += decodedChar;
              utf8Buffer.clear();
              selectedIndex = 0;
              dropdownDismissed = false;
              render();
            } catch (_) {
              if (utf8Buffer.length >= 4) {
                buffer += utf8.decode(utf8Buffer, allowMalformed: true);
                utf8Buffer.clear();
                render();
              }
            }
          }
        }
      }
    } finally {
      clearDropdown();
      // Restore normal terminal modes
      stdout.write('\x1b[?2004l');
      stdin.lineMode = previousLineMode;
      stdin.echoMode = previousEchoMode;
    }

    return buffer.isEmpty ? null : buffer;
  }
}
