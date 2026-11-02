import 'dart:io';
import '../constants/app_version.dart';
import 'command_catalog.dart';

/// Retro Terminal UI inspired by Claude Code and classic phosphor/amber CRT consoles.
class TerminalUI {
  // ANSI Styling Codes
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const italic = '\x1B[3m';
  static const underline = '\x1B[4m';

  // Retro Color Palette
  static const amber = '\x1B[38;5;214m';
  static const brightAmber = '\x1B[38;5;220m';
  static const cyan = '\x1B[38;5;51m';
  static const brightCyan = '\x1B[38;5;87m';
  static const green = '\x1B[38;5;82m';
  static const brightGreen = '\x1B[38;5;120m';
  static const red = '\x1B[38;5;196m';
  static const magenta = '\x1B[38;5;177m';
  static const gray = '\x1B[38;5;245m';
  static const darkGray = '\x1B[38;5;238m';

  static bool get supportsAnsi {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  }

  /// Width used by menus and help cards. Wide terminals get more breathing
  /// room, narrow ones stay readable instead of spilling past the border.
  static int get menuWidth {
    var columns = 80;
    try {
      if (stdout.hasTerminal) columns = stdout.terminalColumns;
    } catch (_) {}
    return (columns - 2).clamp(60, 96);
  }

  /// Truncates to a visible width, keeping a single ellipsis when needed.
  static String fit(String text, int width) {
    if (width <= 0) return '';
    if (text.length <= width) return text;
    if (width == 1) return '…';
    return '${text.substring(0, width - 1)}…';
  }

  /// Pads a styled line to a visible width (ANSI codes are ignored).
  static String padVisible(String styledText, int width) {
    final visible = _stripAnsi(styledText).length;
    if (visible >= width) return styledText;
    return '$styledText${' ' * (width - visible)}';
  }

  static String groupHeader(CommandGroup group, int contentWidth) {
    final dashCount = (contentWidth - group.label.length - 3).clamp(0, 200);
    return '  ${style(group.label, gray + bold)} ${style('─' * dashCount, darkGray)}';
  }

  /// Stylizes a string if terminal supports ANSI escapes
  static String style(String text, String ansiCode) {
    if (!supportsAnsi) return text;
    return '$ansiCode$text$reset';
  }

  /// Interactive shell welcome banner with retro ASCII art
  static void printShellHeader() {
    stdout.writeln();
    stdout.writeln(
      style(r'  ____                               _        ', amber + bold),
    );
    stdout.writeln(
      style(r' / ___|___  _ ____   _____ _ __| |_ ___  ', amber + bold),
    );
    stdout.writeln(
      style(r'| |   / _ \| `_ \ \ / / _ \ `__| __/ _ \ ', amber + bold),
    );
    stdout.writeln(
      style(r'| |__| (_) | | | \ V /  __/ |  | || (_) |', brightAmber + bold),
    );
    stdout.writeln(
      style(r' \____\___/|_| |_|\_/ \___|_|   \__\___/ ', brightAmber + bold),
    );
    stdout.writeln();
    stdout.writeln(
      '  ${style('converto', amber + bold)} ${style('v$appVersion', gray)}'
      '  ${style('·', darkGray)}  ${style('${convertoCommands.length} commands', gray)}',
    );
    stdout.writeln(style('  ${'─' * (menuWidth - 4)}', darkGray));
    stdout.writeln();
  }

  /// Prints the retro Converto logo and banner
  static void printBanner() {
    stdout.writeln();
    stdout.writeln(
      style(r'  ____                               _        ', amber + bold),
    );
    stdout.writeln(
      style(r' / ___|___  _ ____   _____ _ __| |_ ___  ', amber + bold),
    );
    stdout.writeln(
      style(r'| |   / _ \| `_ \ \ / / _ \ `__| __/ _ \ ', amber + bold),
    );
    stdout.writeln(
      style(r'| |__| (_) | | | \ V /  __/ |  | || (_) |', brightAmber + bold),
    );
    stdout.writeln(
      style(r' \____\___/|_| |_|\_/ \___|_|   \__\___/ ', brightAmber + bold),
    );
    stdout.writeln();

    printBox(
      title: 'Converto v$appVersion',
      lines: [
        '100% Offline Local File Converter CLI',
        'Air-gapped verified • Zero network requests • Apache 2.0',
      ],
      borderColor: cyan,
    );
    stdout.writeln();
  }

  /// Prints a Claude Code-style rounded box
  static void printBox({
    required String title,
    required List<String> lines,
    String borderColor = darkGray,
    int width = 64,
  }) {
    final titleFormatted = ' $title ';
    final topBorderLen = width - titleFormatted.length - 3;
    final topBorder = topBorderLen > 0 ? '─' * topBorderLen : '─';

    stdout.writeln(style('╭─$titleFormatted$topBorder╮', borderColor));

    for (final line in lines) {
      final stripped = _stripAnsi(line);
      final padLen = (width - stripped.length - 3).clamp(0, 500);
      final padding = ' ' * padLen;
      stdout.writeln(
        style('│ ', borderColor) + line + padding + style('│', borderColor),
      );
    }

    stdout.writeln(style('╰${"─" * (width - 2)}╯', borderColor));
  }

  /// Step progress indicator (e.g. "◆ Reading input...")
  static void step(String message) {
    stdout.writeln(style(' ◆ ', cyan + bold) + message);
  }

  /// Success message with execution duration
  static void success(String message, {int? elapsedMs}) {
    final timer = elapsedMs != null ? style(' (${elapsedMs}ms)', gray) : '';
    stdout.writeln(style(' ✔ ', green + bold) + style(message, bold) + timer);
  }

  /// Error message callout
  static void error(String message, {String? hint}) {
    stdout.writeln();
    stdout.writeln(style(' ✖ ', red + bold) + style(message, bold));
    if (hint != null) {
      stdout.writeln(style('   hint: ', gray) + style(hint, dim));
    }
    stdout.writeln();
  }

  /// Draws an in-place retro block progress bar
  static void printProgressBar(double progress, {String label = ''}) {
    final pct = (progress * 100).toInt().clamp(0, 100);
    const barWidth = 20;
    final filled = (barWidth * (pct / 100)).round().clamp(0, barWidth);
    final empty = barWidth - filled;

    final bar = style('█' * filled, brightCyan) + style('░' * empty, darkGray);
    stdout.write('\r ${style('⠹', amber)} $bar ${style('$pct%', bold)} $label');
    if (pct >= 100) stdout.writeln();
  }

  /// Displays a formatted result summary card
  static void printSummaryCard({
    required String action,
    required String inputPath,
    required int inputBytes,
    required String outputPath,
    required int outputBytes,
    required int elapsedMs,
    String? engineName,
  }) {
    stdout.writeln();

    final inSizeStr = _formatBytes(inputBytes);
    final outSizeStr = _formatBytes(outputBytes);
    final deltaPct = inputBytes > 0
        ? (((outputBytes - inputBytes) / inputBytes) * 100).toStringAsFixed(1)
        : '0.0';
    final sign = double.tryParse(deltaPct)! > 0 ? '+' : '';
    final deltaDisplay = ' ($sign$deltaPct%)';

    final lines = [
      '${style("Action:   ", gray)}${style(action, bold)}',
      '${style("Input:    ", gray)}$inputPath ${style("($inSizeStr)", dim)}',
      '${style("Output:   ", gray)}${style(outputPath, brightGreen)} ${style("($outSizeStr$deltaDisplay)", cyan)}',
      '${style("Duration: ", gray)}${elapsedMs}ms',
    ];

    if (engineName != null) {
      lines.add('${style("Engine:   ", gray)}$engineName');
    }

    printBox(title: 'Conversion Complete', lines: lines, borderColor: green);
    stdout.writeln();
  }

  /// Clears the terminal screen and resets cursor position
  static void clearScreen() {
    if (supportsAnsi) {
      stdout.write('\x1B[2J\x1B[H');
    }
  }

  /// Displays the available tools, grouped by what the user is trying to do.
  static void printSlashCommands() {
    final width = menuWidth;
    final contentWidth = width - 3;
    const commandWidth = 15;
    const argsWidth = 20;
    final descWidth = (contentWidth - commandWidth - argsWidth - 2).clamp(
      10,
      100,
    );

    final lines = <String>[];
    CommandGroup? activeGroup;
    for (final item in convertoCommands) {
      if (item.group != activeGroup) {
        lines.add(groupHeader(item.group, contentWidth));
        activeGroup = item.group;
      }
      final command = style(item.command.padRight(commandWidth), amber + bold);
      final args = style(item.args.padRight(argsWidth), gray);
      final desc = style(fit(item.desc, descWidth), dim);
      lines.add('  $command$args$desc');
    }

    printBox(title: 'Tools', lines: lines, borderColor: amber, width: width);
    stdout.writeln(
      style('  Drop files anywhere, or try: /convert budget.csv pdf', gray),
    );
  }

  static String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
