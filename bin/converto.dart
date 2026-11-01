import 'dart:io';
import 'package:args/args.dart';
import 'package:converto/core/terminal/slash_prompt.dart';
import 'package:converto/core/terminal/terminal_input.dart';
import 'package:args/command_runner.dart';
import 'package:converto/core/constants/format_types.dart';
import 'package:converto/core/platform/platform_detector.dart';
import 'package:converto/core/terminal/interactive_shell.dart';
import 'package:converto/core/terminal/terminal_ui.dart';
import 'package:converto/core/utils/file_utils.dart';
import 'package:converto/models/edit_options.dart';
import 'package:converto/services/converters/image_converter.dart';
import 'package:converto/services/converters/pdf_converter.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'package:converto/services/file_operations.dart';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on TerminalInterrupted {
    exitCode = 130;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } catch (e) {
    TerminalUI.error(PdfEngine.errorMessage(e));
    exitCode = 1;
  } finally {
    await TerminalInput.dispose();
    await PdfEngine.dispose();
  }
}

Future<void> _run(List<String> args) async {
  // If invoked with no arguments in a terminal, launch the retro slash command shell
  if (args.isEmpty) {
    if (stdin.hasTerminal) {
      await InteractiveShell.start();
      return;
    }
  }

  // Shorthand syntax support: Check if args contain files (single or multi-file drag & drop)
  if (args.isNotEmpty) {
    final firstArg = args.first;

    // Direct privacy verification
    if (firstArg == '--privacy' || firstArg == 'privacy') {
      InteractiveShell.showPrivacyVerification();
      await stdout.flush();
      return;
    }

    if (args.length == 1 && (firstArg == '--version' || firstArg == '-v')) {
      stdout.writeln('Converto 1.0.0  ·  100% offline  ·  Apache 2.0');
      return;
    }

    const knownCommands = {
      'convert',
      'merge',
      'split',
      'extract',
      'organize',
      'rotate',
      'crop',
      'compress',
      'watermark',
      'page-numbers',
      'protect',
      'unlock',
      'pdf2img',
      'pdf2text',
      'pdf2office',
      'pdfa',
      'redact',
      'info',
      'edit-image',
      'formats',
      'privacy',
      'interactive',
      'help',
      '--help',
      '-h',
      '--version',
      '-v',
    };

    if (!knownCommands.contains(firstArg)) {
      final ok = await InteractiveShell.handleArguments(args);
      exitCode = ok ? 0 : 1;
      return;
    }
  }

  final runner =
      CommandRunner(
          'converto',
          'Converto - 100% Offline Local File Converter CLI for Android, Windows, macOS, and Linux.',
        )
        ..addCommand(ConvertCommand())
        ..addCommand(MergeCommand())
        ..addCommand(SplitCommand())
        ..addCommand(ExtractCommand())
        ..addCommand(OrganizeCommand())
        ..addCommand(RotateCommand())
        ..addCommand(CropCommand())
        ..addCommand(CompressCommand())
        ..addCommand(WatermarkCommand())
        ..addCommand(PageNumbersCommand())
        ..addCommand(ProtectCommand())
        ..addCommand(UnlockCommand())
        ..addCommand(PdfToImageCommand())
        ..addCommand(PdfToTextCommand())
        ..addCommand(PdfToOfficeCommand())
        ..addCommand(PdfACommand())
        ..addCommand(RedactCommand())
        ..addCommand(InfoCommand())
        ..addCommand(EditImageCommand())
        ..addCommand(FormatsCommand())
        ..addCommand(InteractiveCommand());

  await runner.run(args);
}

/// Convert Command
class ConvertCommand extends Command {
  @override
  final name = 'convert';
  @override
  final description = 'Convert any supported file to a target format.';

  ConvertCommand() {
    argParser
      ..addOption(
        'to',
        abbr: 't',
        mandatory: true,
        help: 'Target format extension (e.g. pdf, png, jpg, csv, txt)',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Explicit destination file or directory path',
      )
      ..addOption(
        'quality',
        abbr: 'q',
        defaultsTo: '85',
        help: 'Compression quality (1-100) for image output',
      );
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException(
        'Please provide a source file path to convert.',
        usage,
      );
    }

    final sourcePath = InteractiveShell.sanitizeToken(rest.first);
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync() && !Directory(sourcePath).existsSync()) {
      final similar = FileUtils.findSimilarFile(sourcePath);
      TerminalUI.error(
        'File not found at "$sourcePath"',
        hint: similar != null
            ? 'Did you mean: "${similar.path}"?\n   Tip: You can simply drag and drop the file directly into this terminal window!'
            : 'Tip: You can simply drag and drop the file directly into this terminal window!',
      );
      exit(1);
    }

    final targetFormat = argResults!['to'] as String;
    final outputPath = argResults!['output'] as String?;
    final quality = int.parse(argResults!['quality'] as String? ?? '85');
    if (rest.length > 1 || Directory(sourcePath).existsSync()) {
      final ok = await InteractiveShell.handleArguments([
        ...rest.map(InteractiveShell.sanitizeToken),
        targetFormat,
        if (outputPath != null) ...['-o', outputPath],
        '-q',
        '$quality',
      ]);
      exitCode = ok ? 0 : 1;
      return;
    }

    final fromExt = FileUtils.getExtension(sourceFile.path);
    TerminalUI.step(
      'Converting ${sourceFile.path} (.$fromExt) → .$targetFormat ...',
    );

    final stopwatch = Stopwatch()..start();

    File? result;
    final String engineName = 'Local Conversion Engine';
    final inBytes = sourceFile.lengthSync();

    result = await FileOperations.convert(
      sourceFile: sourceFile,
      targetFormat: targetFormat,
      outputPath: outputPath,
      quality: quality,
      onProgress: _printProgress,
    );

    stopwatch.stop();

    TerminalUI.printSummaryCard(
      action: 'Convert (.$fromExt → .$targetFormat)',
      inputPath: sourceFile.path,
      inputBytes: inBytes,
      outputPath: result.path,
      outputBytes: result.lengthSync(),
      elapsedMs: stopwatch.elapsedMilliseconds,
      engineName: engineName,
    );
  }
}

/// Merge Command
class MergeCommand extends Command {
  @override
  final name = 'merge';
  @override
  final description =
      'Merge multiple PDF documents or images into a single PDF.';

  MergeCommand() {
    argParser..addOption(
      'output',
      abbr: 'o',
      mandatory: true,
      help: 'Output PDF file path',
    );
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      throw UsageException('Merge requires at least two input files.', usage);
    }

    final files = rest
        .map((p) => File(InteractiveShell.sanitizeToken(p)))
        .toList();
    for (final f in files) {
      if (!f.existsSync()) {
        TerminalUI.error('File not found at ${f.path}');
        exit(1);
      }
    }

    final outputPath = argResults!['output'] as String;
    TerminalUI.step('Merging ${files.length} files into $outputPath ...');

    final stopwatch = Stopwatch()..start();
    final result = await FileOperations.merge(
      files: files,
      outputPath: outputPath,
      onProgress: _printProgress,
    );

    stopwatch.stop();
    TerminalUI.success(
      'Merged ${files.length} files successfully!',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    stdout.writeln(
      '  ${TerminalUI.style("Saved:", TerminalUI.gray)} ${result.path} (${FileUtils.formatBytes(result.lengthSync())})',
    );
  }
}

/// Split Command
class SplitCommand extends _PdfToolCommand {
  @override
  final name = 'split';
  @override
  final description =
      'Split a PDF by page count, page ranges, or maximum part size.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption('every', abbr: 'e', help: 'Pages per part (default 1)')
      ..addOption(
        'pages',
        abbr: 'p',
        help: 'One-based ranges, e.g. "1-3,5,8-10"',
      )
      ..addOption(
        'size',
        abbr: 's',
        help: 'Maximum size per part, e.g. 5MB or 500KB',
      )
      ..addOption('output', abbr: 'o', help: 'Output directory');
  }

  @override
  Future<String> execute(File source) async {
    final pages = argResults!['pages'] as String?;
    final size = argResults!['size'] as String?;
    final every = argResults!['every'] as String?;

    late final List<File> parts;
    if (pages != null) {
      parts = await PdfEngine.splitExpression(
        sourceFile: source,
        expression: pages,
        outputDirectory: argResults!['output'] as String?,
        onProgress: _printProgress,
      );
    } else if (size != null) {
      parts = await PdfEngine.splitBySize(
        sourceFile: source,
        maxBytes: _parseBytes(size),
        outputDirectory: argResults!['output'] as String?,
        onProgress: _printProgress,
      );
    } else {
      parts = await PdfEngine.splitEvery(
        sourceFile: source,
        every: int.parse(every ?? '1'),
        outputDirectory: argResults!['output'] as String?,
        onProgress: _printProgress,
      );
    }

    _printSaved(parts);
    return 'Split into ${parts.length} PDF${parts.length == 1 ? '' : 's'}!';
  }
}

/// Extract Command
class ExtractCommand extends _PdfToolCommand {
  @override
  final name = 'extract';
  @override
  final description = 'Keep selected pages (and their order) in one PDF.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'pages',
        abbr: 'p',
        mandatory: true,
        help: 'One-based pages, e.g. "1-3,5"',
      )
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.extractPages(
      sourceFile: source,
      expression: argResults!['pages'] as String,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'Pages extracted successfully!';
  }
}

/// Organize Command
class OrganizeCommand extends _PdfToolCommand {
  @override
  final name = 'organize';
  @override
  final description = 'Reorder pages, or delete selected pages.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'order',
        help: 'New one-based order, e.g. "3,1,2" (omit pages to remove)',
      )
      ..addOption('delete', help: 'Pages to delete, e.g. "2,5"')
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final order = argResults!['order'] as String?;
    final delete = argResults!['delete'] as String?;
    if (order == null && delete == null) {
      throw UsageException('Provide --order or --delete.', usage);
    }
    if (order != null && delete != null) {
      throw UsageException('Use either --order or --delete, not both.', usage);
    }

    final result = order != null
        ? await PdfEngine.organize(
            sourceFile: source,
            order: order,
            outputPath: argResults!['output'] as String?,
            onProgress: _printProgress,
          )
        : await PdfEngine.deletePages(
            sourceFile: source,
            expression: delete!,
            outputPath: argResults!['output'] as String?,
            onProgress: _printProgress,
          );
    _printSaved([result]);
    return 'Pages organized successfully!';
  }
}

/// Rotate Command
class RotateCommand extends _PdfToolCommand {
  @override
  final name = 'rotate';
  @override
  final description = 'Rotate every page by 90, 180, or 270 degrees.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'degrees',
        abbr: 'd',
        defaultsTo: '90',
        help: 'Rotation in degrees',
      )
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.rotate(
      sourceFile: source,
      degrees: int.parse(argResults!['degrees'] as String),
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'PDF rotated successfully!';
  }
}

/// Crop Command
class CropCommand extends _PdfToolCommand {
  @override
  final name = 'crop';
  @override
  final description = 'Trim page margins by points locally.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption('left', defaultsTo: '0', help: 'Left margin in points')
      ..addOption('top', defaultsTo: '0', help: 'Top margin in points')
      ..addOption('right', defaultsTo: '0', help: 'Right margin in points')
      ..addOption('bottom', defaultsTo: '0', help: 'Bottom margin in points')
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.crop(
      sourceFile: source,
      left: double.parse(argResults!['left'] as String),
      top: double.parse(argResults!['top'] as String),
      right: double.parse(argResults!['right'] as String),
      bottom: double.parse(argResults!['bottom'] as String),
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'PDF cropped successfully!';
  }
}

/// Compress Command
class CompressCommand extends _PdfToolCommand {
  @override
  final name = 'compress';
  @override
  final description = 'Shrink a PDF locally (screen, ebook, print, lossless).';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'level',
        abbr: 'l',
        defaultsTo: 'ebook',
        help: 'screen | ebook | print | lossless',
      )
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.compress(
      sourceFile: source,
      level: argResults!['level'] as String,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    final before = source.lengthSync();
    final after = result.lengthSync();
    if (after >= before) {
      return 'PDF optimized (no size reduction: ${FileUtils.formatBytes(before)} → ${FileUtils.formatBytes(after)})';
    }
    final saved = before > 0 ? ((before - after) / before * 100) : 0;
    return 'Compressed ${saved.toStringAsFixed(1)}% (${FileUtils.formatBytes(before)} → ${FileUtils.formatBytes(after)})';
  }
}

/// Page Numbers Command
class PageNumbersCommand extends _PdfToolCommand {
  @override
  final name = 'page-numbers';
  @override
  final description = 'Add "Page X of N" to the bottom-right of every page.';

  @override
  void configure(ArgParser parser) {
    parser.addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.pageNumbers(
      sourceFile: source,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'Page numbers added successfully!';
  }
}

/// Protect Command
class ProtectCommand extends _PdfToolCommand {
  @override
  final name = 'protect';
  @override
  final description = 'Encrypt a PDF with a password, locally (AES-256).';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'password',
        abbr: 'p',
        help: 'Password (prompted when omitted)',
      )
      ..addOption('owner', help: 'Optional owner password')
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final password =
        (argResults!['password'] as String?) ??
        await _readSecret('Password (not stored): ');
    if (password == null || password.isEmpty) {
      throw UsageException('A password is required.', usage);
    }

    final result = await PdfEngine.protect(
      sourceFile: source,
      password: password,
      ownerPassword: argResults!['owner'] as String?,
      outputPath: argResults!['output'] as String?,
    );
    _printSaved([result]);
    return 'PDF protected successfully!';
  }
}

/// Unlock Command
class UnlockCommand extends _PdfToolCommand {
  @override
  final name = 'unlock';
  @override
  final description = 'Remove a known password from a PDF, locally.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'password',
        abbr: 'p',
        help: 'PDF password (prompted when omitted)',
      )
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final password =
        (argResults!['password'] as String?) ??
        await _readSecret('PDF password: ');
    if (password == null || password.isEmpty) {
      throw UsageException('A password is required.', usage);
    }

    final result = await PdfEngine.unlock(
      sourceFile: source,
      password: password,
      outputPath: argResults!['output'] as String?,
    );
    _printSaved([result]);
    return 'PDF unlocked successfully!';
  }
}

/// PDF to Text Command
class PdfToTextCommand extends _PdfToolCommand {
  @override
  final name = 'pdf2text';
  @override
  final description = 'Extract selectable text from a PDF into a .txt file.';

  @override
  void configure(ArgParser parser) {
    parser.addOption('output', abbr: 'o', help: 'Output .txt path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfConverter().pdfToText(
      pdfFile: source,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'Text extracted successfully!';
  }
}

/// PDF to Office Command
class PdfToOfficeCommand extends _PdfToolCommand {
  @override
  final name = 'pdf2office';
  @override
  final description = 'Convert a PDF to Word, Excel, or PowerPoint locally.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'to',
        abbr: 't',
        defaultsTo: 'docx',
        help: 'docx | xlsx | pptx',
      )
      ..addOption('output', abbr: 'o', help: 'Output document path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.convertToOffice(
      sourceFile: source,
      format: argResults!['to'] as String,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'PDF converted to Office successfully!';
  }
}

/// PDF/A Command
class PdfACommand extends _PdfToolCommand {
  @override
  final name = 'pdfa';
  @override
  final description = 'Convert a PDF to PDF/A for long-term archiving.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption(
        'level',
        defaultsTo: '2',
        help: 'PDF/A conformance level (1, 2, or 3)',
      )
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.convertToPdfA(
      sourceFile: source,
      level: int.parse(argResults!['level'] as String),
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result]);
    return 'PDF/A conversion complete!';
  }
}

/// Redact Command
class RedactCommand extends _PdfToolCommand {
  @override
  final name = 'redact';
  @override
  final description = 'Permanently remove every occurrence of a text string.';

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption('text', abbr: 't', mandatory: true, help: 'Text to redact')
      ..addOption('output', abbr: 'o', help: 'Output PDF path');
  }

  @override
  Future<String> execute(File source) async {
    final result = await PdfEngine.redactText(
      sourceFile: source,
      query: argResults!['text'] as String,
      outputPath: argResults!['output'] as String?,
      onProgress: _printProgress,
    );
    _printSaved([result.file]);
    return 'Redacted ${result.matches} match${result.matches == 1 ? '' : 'es'} permanently!';
  }
}

/// Info Command
class InfoCommand extends _PdfToolCommand {
  @override
  final name = 'info';
  @override
  final description = 'Show PDF page count, size, metadata, and encryption.';

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'password',
      abbr: 'p',
      help: 'Password for an encrypted PDF',
    );
  }

  @override
  Future<String> execute(File source) async {
    final info = await PdfEngine.info(
      source,
      password: argResults!['password'] as String?,
    );
    TerminalUI.printBox(
      title: 'PDF Details',
      lines: [
        '${TerminalUI.style("File:      ", TerminalUI.gray)}${source.path}',
        '${TerminalUI.style("Size:      ", TerminalUI.gray)}${FileUtils.formatBytes(source.lengthSync())}',
        '${TerminalUI.style("Pages:     ", TerminalUI.gray)}${info.pageCount}',
        '${TerminalUI.style("Version:   ", TerminalUI.gray)}${info.version}',
        '${TerminalUI.style("Page size: ", TerminalUI.gray)}${info.firstPageWidth.toStringAsFixed(0)} × ${info.firstPageHeight.toStringAsFixed(0)} pt${info.rotation != 0 ? ' (rotated ${info.rotation}°)' : ''}',
        '${TerminalUI.style("Encrypted: ", TerminalUI.gray)}${info.isEncrypted ? 'yes' : 'no'}',
        '${TerminalUI.style("Tagged:    ", TerminalUI.gray)}${info.isTagged ? 'yes (accessible)' : 'no'}',
        '${TerminalUI.style("Title:     ", TerminalUI.gray)}${info.title ?? '—'}',
        '${TerminalUI.style("Author:    ", TerminalUI.gray)}${info.author ?? '—'}',
        '${TerminalUI.style("Subject:   ", TerminalUI.gray)}${info.subject ?? '—'}',
      ],
      borderColor: TerminalUI.cyan,
    );
    return 'PDF inspected!';
  }
}

/// Watermark Command
class WatermarkCommand extends Command {
  @override
  final name = 'watermark';
  @override
  final description = 'Apply a diagonal text watermark to a PDF document.';

  WatermarkCommand() {
    argParser
      ..addOption('text', abbr: 'w', mandatory: true, help: 'Watermark text')
      ..addOption(
        'opacity',
        abbr: 'a',
        defaultsTo: '0.2',
        help: 'Watermark opacity (0.0 to 1.0)',
      )
      ..addOption(
        'angle',
        defaultsTo: '45.0',
        help: 'Rotation angle in degrees',
      )
      ..addOption('output', abbr: 'o', help: 'Output watermarked PDF path');
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Please provide a PDF file to watermark.', usage);
    }

    final sourceFile = File(InteractiveShell.sanitizeToken(rest.first));
    if (!sourceFile.existsSync()) {
      TerminalUI.error('File not found at ${sourceFile.path}');
      exit(1);
    }

    final watermarkText = argResults!['text'] as String;
    final opacity = double.parse(argResults!['opacity'] as String? ?? '0.2');
    final angle = double.parse(argResults!['angle'] as String? ?? '45.0');
    final outputPath = argResults!['output'] as String?;

    TerminalUI.step(
      'Applying watermark "$watermarkText" to ${sourceFile.path} ...',
    );
    final stopwatch = Stopwatch()..start();

    final result = await PdfConverter().applyWatermark(
      pdfFile: sourceFile,
      watermarkText: watermarkText,
      opacity: opacity,
      angle: angle,
      outputPath: outputPath,
      onProgress: _printProgress,
    );

    stopwatch.stop();
    TerminalUI.success(
      'Watermark applied successfully!',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    stdout.writeln(
      '  ${TerminalUI.style("Saved:", TerminalUI.gray)} ${result.path} (${FileUtils.formatBytes(result.lengthSync())})',
    );
  }
}

/// PDF to Image Command
class PdfToImageCommand extends Command {
  @override
  final name = 'pdf2img';
  @override
  final description = 'Rasterize PDF pages into high-DPI images (PNG/JPG).';

  PdfToImageCommand() {
    argParser
      ..addOption(
        'to',
        abbr: 't',
        defaultsTo: 'png',
        help: 'Output format (png or jpg)',
      )
      ..addOption('dpi', defaultsTo: '150', help: 'Rendering DPI resolution')
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory, or a .png/.jpg path for page 1',
      );
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Please provide a PDF file path.', usage);
    }

    final sourceFile = File(InteractiveShell.sanitizeToken(rest.first));
    if (!sourceFile.existsSync()) {
      TerminalUI.error('File not found at ${sourceFile.path}');
      exit(1);
    }

    final targetFormat = argResults!['to'] as String;
    final dpi = int.parse(argResults!['dpi'] as String? ?? '150');
    final outputPath = argResults!['output'] as String?;
    final outputExt = outputPath == null
        ? ''
        : FileUtils.getExtension(outputPath);
    final explicitFile =
        outputPath != null &&
        !Directory(outputPath).existsSync() &&
        ['png', 'jpg', 'jpeg'].contains(outputExt);

    TerminalUI.step(
      'Rasterizing ${sourceFile.path} to .$targetFormat ($dpi DPI) ...',
    );
    final stopwatch = Stopwatch()..start();

    try {
      final results = await PdfEngine.renderPages(
        sourceFile: sourceFile,
        targetFormat: targetFormat,
        dpi: dpi,
        outputDirectory: explicitFile
            ? File(outputPath).parent.path
            : outputPath,
        firstPageOutputPath: explicitFile ? outputPath : null,
        onProgress: _printProgress,
      );

      stopwatch.stop();
      TerminalUI.success(
        'Exported ${results.length} page${results.length == 1 ? '' : 's'}!',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      _printSaved(results);
    } catch (e) {
      TerminalUI.error(
        'PDF rasterization failed: ${PdfEngine.errorMessage(e)}',
      );
      exit(1);
    }
  }
}

/// Edit Image Command
class EditImageCommand extends Command {
  @override
  final name = 'edit-image';
  @override
  final description = 'Rotate, crop, flip, or compress images.';

  EditImageCommand() {
    argParser
      ..addOption(
        'rotate',
        abbr: 'r',
        defaultsTo: '0',
        help: 'Rotation degrees (0, 90, 180, 270)',
      )
      ..addFlag('flip-h', defaultsTo: false, help: 'Flip image horizontally')
      ..addFlag('flip-v', defaultsTo: false, help: 'Flip image vertically')
      ..addOption(
        'quality',
        abbr: 'q',
        defaultsTo: '85',
        help: 'Compression quality (1-100)',
      )
      ..addOption('to', abbr: 't', help: 'Optional target format conversion')
      ..addOption('output', abbr: 'o', help: 'Destination file path');
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Please provide an image file path.', usage);
    }

    final sourceFile = File(InteractiveShell.sanitizeToken(rest.first));
    if (!sourceFile.existsSync()) {
      TerminalUI.error('File not found at ${sourceFile.path}');
      exit(1);
    }

    final rotate = int.parse(argResults!['rotate'] as String? ?? '0');
    final flipH = argResults!['flip-h'] as bool;
    final flipV = argResults!['flip-v'] as bool;
    final quality = int.parse(argResults!['quality'] as String? ?? '85');
    final fromExt = FileUtils.getExtension(sourceFile.path);
    final targetFormat = (argResults!['to'] as String?) ?? fromExt;
    final outputPath = argResults!['output'] as String?;

    final options = ImageEditOptions(
      rotationDegrees: rotate,
      flipHorizontal: flipH,
      flipVertical: flipV,
      compressionQuality: quality,
    );

    TerminalUI.step(
      'Editing ${sourceFile.path} (rotate: $rotate°, flipH: $flipH, flipV: $flipV, q: $quality) ...',
    );
    final stopwatch = Stopwatch()..start();

    final result = await ImageConverter().convert(
      sourceFile: sourceFile,
      targetFormat: targetFormat,
      imageOptions: options,
      outputPath: outputPath,
      onProgress: _printProgress,
    );

    stopwatch.stop();
    TerminalUI.success(
      'Image edited successfully!',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    stdout.writeln(
      '  ${TerminalUI.style("Saved:", TerminalUI.gray)} ${result.path} (${FileUtils.formatBytes(result.lengthSync())})',
    );
  }
}

/// Formats Command
class FormatsCommand extends Command {
  @override
  final name = 'formats';
  @override
  final description =
      'List all supported formats and platform engine capabilities.';

  @override
  Future<void> run() async {
    final caps = await PlatformDetector.detect();

    TerminalUI.printBanner();

    TerminalUI.printBox(
      title: 'Platform Capabilities',
      lines: [
        '${TerminalUI.style("Platform:        ", TerminalUI.gray)}${caps.isWindows ? "Windows" : (caps.isAndroid ? "Android" : (caps.isMacOS ? "macOS" : "Linux"))}',
        '${TerminalUI.style("PDF Engine:      ", TerminalUI.gray)}${TerminalUI.style("● Bundled native engine (offline)", TerminalUI.green)}',
        '${TerminalUI.style("LibreOffice CLI: ", TerminalUI.gray)}${caps.hasLibreOfficeCLI ? TerminalUI.style("● Available (${caps.libreOfficePath})", TerminalUI.green) : TerminalUI.style("○ Fallback active", TerminalUI.gray)}',
      ],
      borderColor: TerminalUI.cyan,
    );

    final formatsByCategory = <FileCategory, List<String>>{};
    for (final entry in FormatRegistry.formats.entries) {
      formatsByCategory
          .putIfAbsent(entry.value.category, () => [])
          .add(entry.key.toUpperCase());
    }

    final formatLines = <String>[];
    for (final cat in formatsByCategory.entries) {
      final name = '${cat.key.name.toUpperCase()}:'.padRight(16);
      formatLines.add(
        '${TerminalUI.style(name, TerminalUI.amber + TerminalUI.bold)}${cat.value.join(", ")}',
      );
    }

    TerminalUI.printBox(
      title: 'Supported Formats',
      lines: formatLines,
      borderColor: TerminalUI.amber,
    );
  }
}

/// Interactive Command
class InteractiveCommand extends Command {
  @override
  final name = 'interactive';
  @override
  final description = 'Launch the interactive retro studio terminal UI.';

  @override
  Future<void> run() async {
    await InteractiveShell.start();
  }
}

abstract class _PdfToolCommand extends Command {
  _PdfToolCommand() {
    configure(argParser);
  }

  void configure(ArgParser parser) {}

  Future<String> execute(File source);

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Please provide a PDF file path.', usage);
    }

    final source = _requirePdf(rest.first);
    TerminalUI.step('${name.toUpperCase()}: ${source.path}');
    final stopwatch = Stopwatch()..start();

    try {
      final message = await execute(source);
      stopwatch.stop();
      TerminalUI.success(message, elapsedMs: stopwatch.elapsedMilliseconds);
    } catch (e) {
      TerminalUI.error('$name failed: ${PdfEngine.errorMessage(e)}');
      await stdout.flush();
      exit(1);
    }
  }
}

File _requirePdf(String path) {
  final file = File(InteractiveShell.sanitizeToken(path));
  if (!file.existsSync()) {
    final similar = FileUtils.findSimilarFile(path);
    TerminalUI.error(
      'File not found: "$path"',
      hint: similar != null ? 'Did you mean: "${similar.path}"?' : null,
    );
    exit(1);
  }
  if (FileUtils.getExtension(file.path) != 'pdf') {
    TerminalUI.error('That is not a PDF file.');
    exit(1);
  }
  return file;
}

void _printSaved(List<File> files) {
  for (final file in files) {
    stdout.writeln(
      '  ${TerminalUI.style('Saved:', TerminalUI.gray)} ${file.path} '
      '(${FileUtils.formatBytes(file.lengthSync())})',
    );
  }
}

int _parseBytes(String raw) {
  final match = RegExp(
    r'^\s*([0-9]+(?:\.[0-9]+)?)\s*(b|kb|mb|gb)?\s*$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    throw UsageException('Use a size such as 500KB, 5MB, or 1GB.', '');
  }

  final value = double.parse(match.group(1)!);
  final unit = (match.group(2) ?? 'b').toLowerCase();
  final multiplier = switch (unit) {
    'kb' => 1024,
    'mb' => 1024 * 1024,
    'gb' => 1024 * 1024 * 1024,
    _ => 1,
  };
  return (value * multiplier).round();
}

Future<String?> _readSecret(String label) async {
  stdout.write(label);
  final interactive = stdin.hasTerminal;
  try {
    if (interactive) stdin.echoMode = false;
    final value = (await SlashPrompt.readPlainLine());
    if (interactive) {
      stdin.echoMode = true;
      stdout.writeln();
    }
    return value;
  } finally {
    if (interactive) stdin.echoMode = true;
  }
}

void _printProgress(double progress) {
  TerminalUI.printProgressBar(progress);
}
