/// Single source of truth for the tools shown in the interactive shell.
///
/// The catalog only describes presentation and discovery. Every command is
/// still handled by [InteractiveShell], so adding a tool here never changes
/// what the CLI can actually do.
enum CommandGroup {
  convert('CONVERT'),
  organize('ORGANIZE'),
  edit('EDIT'),
  security('SECURITY'),
  info('INFO'),
  session('SESSION');

  final String label;
  const CommandGroup(this.label);
}

class SlashCommandItem {
  final String command;
  final String args;
  final String desc;
  final bool requiresArgs;
  final CommandGroup group;

  const SlashCommandItem({
    required this.command,
    required this.args,
    required this.desc,
    required this.group,
    this.requiresArgs = false,
  });
}

const List<SlashCommandItem> convertoCommands = [
  // CONVERT
  SlashCommandItem(
    command: '/convert',
    args: '<file> [format]',
    desc: 'Convert any supported file',
    requiresArgs: true,
    group: CommandGroup.convert,
  ),
  SlashCommandItem(
    command: '/pdf2img',
    args: '<pdf> [fmt] [dpi]',
    desc: 'Export every PDF page',
    requiresArgs: true,
    group: CommandGroup.convert,
  ),
  SlashCommandItem(
    command: '/pdf2text',
    args: '<pdf>',
    desc: 'Extract text from a PDF',
    requiresArgs: true,
    group: CommandGroup.convert,
  ),
  SlashCommandItem(
    command: '/pdf2office',
    args: '<pdf> [docx]',
    desc: 'PDF to Word, Excel, or PPT',
    requiresArgs: true,
    group: CommandGroup.convert,
  ),

  // ORGANIZE
  SlashCommandItem(
    command: '/merge',
    args: '<files...>',
    desc: 'Combine PDFs or images',
    requiresArgs: true,
    group: CommandGroup.organize,
  ),
  SlashCommandItem(
    command: '/split',
    args: '<pdf> [--every N]',
    desc: 'Split by pages, ranges, or size',
    requiresArgs: true,
    group: CommandGroup.organize,
  ),
  SlashCommandItem(
    command: '/extract',
    args: '<pdf> <pages>',
    desc: 'Keep selected pages in one PDF',
    requiresArgs: true,
    group: CommandGroup.organize,
  ),
  SlashCommandItem(
    command: '/organize',
    args: '<pdf> [--order]',
    desc: 'Reorder or delete pages',
    requiresArgs: true,
    group: CommandGroup.organize,
  ),
  SlashCommandItem(
    command: '/rotate',
    args: '<pdf> [degrees]',
    desc: 'Rotate every page',
    requiresArgs: true,
    group: CommandGroup.organize,
  ),

  // EDIT
  SlashCommandItem(
    command: '/watermark',
    args: '<pdf> [text]',
    desc: 'Stamp text on every page',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/page-numbers',
    args: '<pdf>',
    desc: 'Add Page X of N numbers',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/crop',
    args: '<pdf> <margins>',
    desc: 'Trim page margins (points)',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/compress',
    args: '<pdf> [level]',
    desc: 'Shrink PDF images and streams',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/redact',
    args: '<pdf> <text>',
    desc: 'Permanently remove text matches',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/pdfa',
    args: '<pdf> [level]',
    desc: 'Convert to a PDF/A archive',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),
  SlashCommandItem(
    command: '/edit',
    args: '<image>',
    desc: 'Rotate, flip, compress images',
    requiresArgs: true,
    group: CommandGroup.edit,
  ),

  // SECURITY
  SlashCommandItem(
    command: '/protect',
    args: '<pdf>',
    desc: 'Add a password locally',
    requiresArgs: true,
    group: CommandGroup.security,
  ),
  SlashCommandItem(
    command: '/unlock',
    args: '<pdf>',
    desc: 'Remove a known PDF password',
    requiresArgs: true,
    group: CommandGroup.security,
  ),

  // INFO
  SlashCommandItem(
    command: '/info',
    args: '<pdf>',
    desc: 'Pages, size, metadata, encryption',
    requiresArgs: true,
    group: CommandGroup.info,
  ),
  SlashCommandItem(
    command: '/formats',
    args: '',
    desc: 'Formats & engine status',
    group: CommandGroup.info,
  ),
  SlashCommandItem(
    command: '/privacy',
    args: '',
    desc: 'Air-gap & privacy verification',
    group: CommandGroup.info,
  ),
  SlashCommandItem(
    command: '/recent',
    args: '',
    desc: 'Recent conversions',
    group: CommandGroup.info,
  ),
  SlashCommandItem(
    command: '/help',
    args: '',
    desc: 'Show all tools & examples',
    group: CommandGroup.info,
  ),

  // SESSION
  SlashCommandItem(
    command: '/clear',
    args: '',
    desc: 'Clear the screen',
    group: CommandGroup.session,
  ),
  SlashCommandItem(
    command: '/exit',
    args: '',
    desc: 'Exit Converto',
    group: CommandGroup.session,
  ),
];

List<SlashCommandItem> filterCommands(String input) {
  final query = input.trim().toLowerCase();
  return convertoCommands
      .where((cmd) => cmd.command.startsWith(query))
      .toList(growable: false);
}

/// Returns the closest command for a mistyped slash command, if one is close.
String? suggestCommand(String input) {
  final token = input.trim().split(RegExp(r'\s+')).first.toLowerCase();
  if (!token.startsWith('/') || token == '/') return null;

  for (final cmd in convertoCommands) {
    if (cmd.command == token) return null;
  }

  // A prefix is always the most useful suggestion: /pdf2 -> /pdf2img.
  for (final cmd in convertoCommands) {
    if (cmd.command.startsWith(token)) return cmd.command;
  }

  String? bestCommand;
  var bestDistance = 3;
  for (final cmd in convertoCommands) {
    final distance = _levenshtein(token, cmd.command);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestCommand = cmd.command;
    }
  }
  return bestCommand;
}

int _levenshtein(String a, String b) {
  final rows = List<int>.generate(b.length + 1, (i) => i);

  for (var i = 1; i <= a.length; i++) {
    var previous = rows[0];
    rows[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final current = rows[j];
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      rows[j] = [
        rows[j] + 1,
        rows[j - 1] + 1,
        previous + cost,
      ].reduce((x, y) => x < y ? x : y);
      previous = current;
    }
  }

  return rows[b.length];
}
