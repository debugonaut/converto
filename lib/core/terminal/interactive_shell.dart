import 'dart:io';
import 'package:converto/core/constants/format_types.dart';
import 'package:converto/core/platform/platform_detector.dart';
import 'package:converto/core/utils/file_utils.dart';
import 'package:converto/models/edit_options.dart';
import 'package:converto/services/converters/image_converter.dart';
import 'package:converto/services/converters/pdf_converter.dart';
import 'package:converto/services/history_service.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'package:converto/services/storage_service.dart';
import 'package:converto/services/file_operations.dart';
import 'input_parser.dart';
import 'terminal_input.dart';
import 'command_catalog.dart';
import 'slash_prompt.dart';
import 'terminal_ui.dart';

class InteractiveShell {
  static Future<void> start() async {
    _printWelcome();

    while (true) {
      final line = await SlashPrompt.readLine();
      if (line == null) break;

      final input = line.trim();
      if (input.isEmpty) continue;

      // Exit checks
      if (input == '/exit' ||
          input == '/quit' ||
          input == 'exit' ||
          input == 'q') {
        stdout.writeln(
          TerminalUI.style('Goodbye! Converto session closed.', TerminalUI.dim),
        );
        break;
      }

      // Clear screen
      if (input == '/clear' || input == 'clear') {
        TerminalUI.clearScreen();
        _printWelcome();
        continue;
      }

      // Slash commands help
      if (input == '/' || input == '/help' || input == 'help') {
        TerminalUI.printSlashCommands();
        stdout.writeln();
        continue;
      }

      // Recent history
      if (input == '/recent' || input == 'recent') {
        await _showRecentHistory();
        continue;
      }

      // Formats matrix
      if (input == '/formats' || input == 'formats') {
        await _showFormats();
        continue;
      }

      // Privacy verification
      if (input == '/privacy' || input == 'privacy') {
        showPrivacyVerification();
        continue;
      }

      try {
        // Parse slash commands or direct file inputs. Match the exact command
        // token so a typo like /convertx gets a suggestion instead of being
        // treated as a convert with a file called "x". Absolute paths (the way
        // Finder and Explorer drag & drop files) must stay file paths.
        final tokens = tokenize(input);
        final firstToken = tokens.firstOrNull ?? '';
        final isSlashCommand =
            firstToken.startsWith('/') &&
            firstToken.indexOf('/', 1) == -1 &&
            !firstToken.contains('.') &&
            !File(firstToken).existsSync() &&
            !Directory(firstToken).existsSync();
        final slashCommand = isSlashCommand ? firstToken.toLowerCase() : '';
        final commandArgs = isSlashCommand && input.length > firstToken.length
            ? input
                  .substring(input.indexOf(firstToken) + firstToken.length)
                  .trim()
            : '';

        if (slashCommand == '/convert') {
          await _parseConvertCommand(commandArgs);
        } else if (slashCommand == '/merge') {
          await _parseMergeCommand(commandArgs);
        } else if (slashCommand == '/split') {
          await _parseSplitCommand(commandArgs);
        } else if (slashCommand == '/extract') {
          await _parseExtractCommand(commandArgs);
        } else if (slashCommand == '/organize') {
          await _parseOrganizeCommand(commandArgs);
        } else if (slashCommand == '/rotate') {
          await _parseRotateCommand(commandArgs);
        } else if (slashCommand == '/crop') {
          await _parseCropCommand(commandArgs);
        } else if (slashCommand == '/compress') {
          await _parseCompressCommand(commandArgs);
        } else if (slashCommand == '/watermark') {
          await _parseWatermarkCommand(commandArgs);
        } else if (slashCommand == '/page-numbers') {
          await _parsePageNumbersCommand(commandArgs);
        } else if (slashCommand == '/protect') {
          await _parseProtectCommand(commandArgs);
        } else if (slashCommand == '/unlock') {
          await _parseUnlockCommand(commandArgs);
        } else if (slashCommand == '/pdf2img') {
          await _parsePdf2ImgCommand(commandArgs);
        } else if (slashCommand == '/pdf2text') {
          await _parsePdf2TextCommand(commandArgs);
        } else if (slashCommand == '/pdf2office') {
          await _parsePdf2OfficeCommand(commandArgs);
        } else if (slashCommand == '/pdfa') {
          await _parsePdfaCommand(commandArgs);
        } else if (slashCommand == '/redact') {
          await _parseRedactCommand(commandArgs);
        } else if (slashCommand == '/info') {
          await _parseInfoCommand(commandArgs);
        } else if (slashCommand == '/edit') {
          await _parseEditCommand(commandArgs);
        } else if (slashCommand == '/help') {
          TerminalUI.printSlashCommands();
          stdout.writeln();
        } else if (slashCommand.startsWith('/')) {
          final suggestion = suggestCommand(slashCommand);
          TerminalUI.error(
            'Unknown command "$slashCommand"',
            hint: suggestion != null
                ? 'Did you mean $suggestion? Type / to see all tools.'
                : 'Type / to see all tools.',
          );
        } else {
          // Direct file path (or drag and drop) handling
          await _handleDirectInput(input);
        }
      } on TerminalInterrupted {
        exitCode = 130;
        break;
      } catch (e) {
        exitCode = 1;
        TerminalUI.error(PdfEngine.errorMessage(e));
      }
      stdout.writeln();
    }
  }

  static void _printWelcome() {
    TerminalUI.printShellHeader();
    stdout.writeln(
      '  ${TerminalUI.style('Drop files here, or type ', TerminalUI.gray)}'
      '${TerminalUI.style('/', TerminalUI.amber + TerminalUI.bold)}'
      '${TerminalUI.style(' for tools.', TerminalUI.gray)}',
    );
    stdout.writeln(
      '  ${TerminalUI.style('Try /convert budget.csv pdf  ·  /merge a.pdf b.pdf  ·  /help', TerminalUI.dim)}',
    );
    stdout.writeln();
  }

  /// Handles direct input: single file drag & drop, multi-file drag & drop, folder drop, or shorthand syntax
  static Future<void> _handleDirectInput(String input) async {
    await handleArguments(tokenize(input), interactive: true);
  }

  static Future<bool> handleArguments(
    List<String> arguments, {
    bool interactive = false,
  }) async {
    final parsed = _parseArgs(
      arguments,
      valueOptions: {'-o', '--output', '-q', '--quality', '--to', '-t'},
    );
    final inputs = parsed.positional;
    final outputPath = _option(parsed, ['--output', '-o']);
    final quality = int.parse(_option(parsed, ['--quality', '-q']) ?? '85');
    String? target = _option(parsed, [
      '--to',
      '-t',
    ])?.replaceFirst('.', '').toLowerCase();
    if (interactive &&
        target == null &&
        outputPath == null &&
        inputs.length == 1 &&
        Directory(inputs.single).existsSync()) {
      await _handleDirectoryInput(Directory(inputs.single), null);
      return true;
    }
    final files = <File>[];
    for (var i = 0; i < inputs.length; i++) {
      final raw = inputs[i];
      final token = (File(raw).existsSync() || Directory(raw).existsSync())
          ? raw
          : TerminalInputParser.normalizePath(raw);
      if (File(token).existsSync()) {
        files.add(File(token));
      } else if (Directory(token).existsSync()) {
        final children = FileUtils.listSupportedFiles(Directory(token));
        if (children.isEmpty)
          throw ArgumentError('No supported files in "$token".');
        files.addAll(children);
      } else if (i == inputs.length - 1 &&
          target == null &&
          RegExp(r'^\.?[a-zA-Z0-9]+$').hasMatch(token)) {
        target = token.replaceFirst('.', '').toLowerCase();
      } else {
        throw ArgumentError('File not found: "$token"');
      }
    }
    if (files.isEmpty)
      throw ArgumentError('Provide a readable source file or folder.');
    if (files.length == 1) {
      if (target != null) {
        return await executeConvert(
              file: files.single,
              targetFormat: target,
              outputPath: outputPath,
              quality: quality,
              interactivePostAction: interactive,
            ) !=
            null;
      }
      if (!stdin.hasTerminal && !interactive) {
        throw ArgumentError(
          'Specify a target format when standard input is not a terminal.',
        );
      }
      return promptFileActions(files.single);
    }
    if (target == 'pdf' || (target == null && !interactive)) {
      if (files.every(FileOperations.canMerge))
        return _executeMergeFiles(files, outputPath: outputPath);
      return batchConvert(
        files,
        target ?? 'pdf',
        outputDirectory: outputPath,
        quality: quality,
        interactivePostAction: interactive,
      );
    }
    if (target != null)
      return batchConvert(
        files,
        target,
        interactivePostAction: interactive,
        outputDirectory: outputPath,
        quality: quality,
      );
    await _handleMultiFileDragAndDrop(files, null);
    return true;
  }

  /// Intelligent handling when a user drags multiple files into the terminal
  static Future<void> _handleMultiFileDragAndDrop(
    List<File> files,
    String? explicitTarget,
  ) async {
    final fileLines = <String>[];
    bool allImagesOrPdfs = true;

    for (final f in files) {
      final ext = FileUtils.getExtension(f.path);
      final size = FileUtils.formatBytes(f.lengthSync());
      final isImgOrPdf = FileOperations.canMerge(f);
      if (!isImgOrPdf) allImagesOrPdfs = false;

      fileLines.add(
        '${TerminalUI.style("•", TerminalUI.amber)} ${FileUtils.getFileName(f.path)} ${TerminalUI.style("($size, .$ext)", TerminalUI.gray)}',
      );
    }

    TerminalUI.printBox(
      title: 'Multiple Files Detected (${files.length} files)',
      lines: fileLines,
      borderColor: TerminalUI.cyan,
    );

    // If explicit target given (e.g. converto f1.png f2.png webp)
    if (explicitTarget != null) {
      if (explicitTarget == 'pdf' && allImagesOrPdfs) {
        // Merge them into PDF
        await _executeMergeFiles(files);
      } else {
        // Batch convert each
        await batchConvert(files, explicitTarget);
      }
      return;
    }

    // Interactive prompt for multi-file action
    if (allImagesOrPdfs) {
      stdout.writeln(
        TerminalUI.style(
          'What would you like to do with these ${files.length} files?',
          TerminalUI.bold,
        ),
      );
      stdout.writeln(
        '  ${TerminalUI.style("[1] Merge into a single PDF (Default - hit Enter)", TerminalUI.brightCyan + TerminalUI.bold)}',
      );
      stdout.writeln(
        '  ${TerminalUI.style("[2] Batch convert each file individually", TerminalUI.gray)}',
      );
      stdout.write(
        '${TerminalUI.style("converto", TerminalUI.cyan)} ${TerminalUI.style("›", TerminalUI.amber)} ',
      );

      final choice =
          (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
      if (choice.isEmpty || choice == '1' || choice == 'merge') {
        await _executeMergeFiles(files);
      } else {
        stdout.write(
          '${TerminalUI.style("Target format for all files (e.g. webp, png, pdf):", TerminalUI.bold)} ',
        );
        final target =
            (await SlashPrompt.readPlainLine())
                ?.trim()
                .toLowerCase()
                .replaceAll('.', '') ??
            'pdf';
        await batchConvert(files, target);
      }
    } else {
      stdout.write(
        '${TerminalUI.style("Batch convert all ${files.length} files to format (or hit Enter for PDF):", TerminalUI.bold)} ',
      );
      final ans =
          (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
      final target = ans.isEmpty ? 'pdf' : ans.replaceAll('.', '');
      await batchConvert(files, target);
    }
  }

  /// Intelligent handling when an entire directory/folder is dropped into the terminal
  static Future<void> _handleDirectoryInput(
    Directory dir,
    String? explicitTarget,
  ) async {
    final supportedFiles = FileUtils.listSupportedFiles(dir);

    if (supportedFiles.isEmpty) {
      TerminalUI.error(
        'No supported convertible files found in "${dir.path}"',
        hint:
            'Converto supports images (png, jpg, webp...), PDFs, docs, spreadsheets, and presentations.',
      );
      return;
    }

    final categoryCounts = <FileCategory, int>{};
    for (final f in supportedFiles) {
      final ext = FileUtils.getExtension(f.path);
      final cat = FormatRegistry.getFormatInfo(ext).category;
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    final summaryParts = categoryCounts.entries
        .map((e) => '${e.value} ${e.key.name}s')
        .join(', ');

    TerminalUI.printBox(
      title:
          'Directory Detected: "${FileUtils.getFileName(dir.path)}" (${supportedFiles.length} files)',
      lines: [
        '${TerminalUI.style("Folder:   ", TerminalUI.gray)}${dir.path}',
        '${TerminalUI.style("Contents: ", TerminalUI.gray)}$summaryParts',
      ],
      borderColor: TerminalUI.cyan,
    );

    // If explicit target given (e.g. converto ./photos webp)
    if (explicitTarget != null) {
      final cleanTarget = explicitTarget.replaceAll('.', '').toLowerCase();
      if (cleanTarget == 'pdf') {
        final allImages = supportedFiles.every(
          (f) =>
              FormatRegistry.getFormatInfo(
                FileUtils.getExtension(f.path),
              ).category ==
              FileCategory.image,
        );
        if (allImages) {
          await _executeMergeFiles(supportedFiles);
          return;
        }
      }
      await batchConvert(supportedFiles, cleanTarget);
      return;
    }

    // Interactive prompt
    final allImages = supportedFiles.every(
      (f) =>
          FormatRegistry.getFormatInfo(
            FileUtils.getExtension(f.path),
          ).category ==
          FileCategory.image,
    );

    if (allImages) {
      stdout.writeln(
        TerminalUI.style(
          'What would you like to do with these ${supportedFiles.length} images?',
          TerminalUI.bold,
        ),
      );
      stdout.writeln(
        '  ${TerminalUI.style("[1] Merge all into a single PDF (Default - hit Enter)", TerminalUI.brightCyan + TerminalUI.bold)}',
      );
      stdout.writeln(
        '  ${TerminalUI.style("[2] Batch convert each image (e.g. to webp/png)", TerminalUI.gray)}',
      );
      stdout.write(
        '${TerminalUI.style("converto", TerminalUI.cyan)} ${TerminalUI.style("›", TerminalUI.amber)} ',
      );

      final choice =
          (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
      if (choice.isEmpty || choice == '1' || choice == 'merge') {
        await _executeMergeFiles(supportedFiles);
      } else {
        stdout.write(
          '${TerminalUI.style("Target format (e.g. webp, png, jpg):", TerminalUI.bold)} ',
        );
        final target =
            (await SlashPrompt.readPlainLine())
                ?.trim()
                .toLowerCase()
                .replaceAll('.', '') ??
            'webp';
        await batchConvert(supportedFiles, target);
      }
    } else {
      stdout.write(
        '${TerminalUI.style("Batch convert all ${supportedFiles.length} files to format (or hit Enter for PDF):", TerminalUI.bold)} ',
      );
      final ans =
          (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
      final target = ans.isEmpty ? 'pdf' : ans.replaceAll('.', '');
      await batchConvert(supportedFiles, target);
    }
  }

  static Future<bool> _executeMergeFiles(
    List<File> files, {
    String? outputPath,
  }) async {
    outputPath ??= 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
    TerminalUI.step('Merging ${files.length} files into $outputPath ...');
    final stopwatch = Stopwatch()..start();

    try {
      final result = await FileOperations.merge(
        files: files,
        outputPath: outputPath,
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Merging PDF pages...'),
      );
      stopwatch.stop();

      TerminalUI.success(
        'Merged ${files.length} files into PDF!',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      await _printSavedFiles([result]);
      return true;
    } catch (e) {
      exitCode = 1;
      TerminalUI.error(
        'Merge failed: $e',
        hint:
            'The bundled PDF engine handles merges locally; no external tools needed.',
      );
      return false;
    }
  }

  /// Shows the actions that actually apply to a single file. The old
  /// "type a target format" path is still option 1, so no capability is lost.
  static Future<bool> promptFileActions(File file) async {
    final ext = FileUtils.getExtension(file.path);
    final formatInfo = FormatRegistry.getFormatInfo(ext);
    final category = formatInfo.category;
    final targets = FormatRegistry.getAvailableTargetFormats(ext);

    TerminalUI.printBox(
      title: 'File Detected',
      lines: [
        '${TerminalUI.style("File:     ", TerminalUI.gray)}${file.path}',
        '${TerminalUI.style("Size:     ", TerminalUI.gray)}${FileUtils.formatBytes(file.lengthSync())}',
        '${TerminalUI.style("Category: ", TerminalUI.gray)}${TerminalUI.style(category.name.toUpperCase(), TerminalUI.amber + TerminalUI.bold)}',
        '${TerminalUI.style("Targets:  ", TerminalUI.gray)}${targets.map((f) => f.toUpperCase()).join(", ")}',
      ],
      borderColor: TerminalUI.cyan,
    );

    final actions = _actionsFor(category);
    stdout.writeln(
      TerminalUI.style('What do you want to do?', TerminalUI.bold),
    );
    for (var i = 0; i < actions.length; i++) {
      stdout.writeln(
        '  ${TerminalUI.style('${i + 1}', TerminalUI.amber + TerminalUI.bold)}  ${actions[i].label}',
      );
    }
    stdout.write(
      '${TerminalUI.style('Choose [1-${actions.length}, Enter = 1]:', TerminalUI.bold)} ',
    );

    final rawAnswer = await SlashPrompt.readPlainLine();
    if (rawAnswer == null) return false;
    final answer = rawAnswer.trim();
    final index = answer.isEmpty ? 0 : (int.tryParse(answer) ?? -1) - 1;
    if (index < 0 || index >= actions.length) {
      TerminalUI.error('Pick a number between 1 and ${actions.length}.');
      return false;
    }

    switch (actions[index].kind) {
      case _FileActionKind.convert:
        return _promptConvert(
          file,
          targets,
          defaultTarget: category == FileCategory.pdf ? 'png' : 'pdf',
        );
      case _FileActionKind.merge:
        return _promptMerge(file, isPdf: category == FileCategory.pdf);
      case _FileActionKind.split:
        return _promptSplit(file);
      case _FileActionKind.compress:
        return _promptCompress(file);
      case _FileActionKind.watermark:
        return _promptWatermark(file);
      case _FileActionKind.exportImages:
        return _promptPdfToImages(file);
      case _FileActionKind.editImage:
        return _promptEditImage(file);
      case _FileActionKind.details:
        _showFileDetails(file, targets);
        return true;
    }
  }

  static List<_FileAction> _actionsFor(FileCategory category) {
    switch (category) {
      case FileCategory.pdf:
        return const [
          _FileAction(
            'Convert or export to another format',
            _FileActionKind.convert,
          ),
          _FileAction('Merge with other PDFs', _FileActionKind.merge),
          _FileAction('Split or extract pages', _FileActionKind.split),
          _FileAction('Compress to a smaller PDF', _FileActionKind.compress),
          _FileAction('Apply a text watermark', _FileActionKind.watermark),
          _FileAction('Export pages as images', _FileActionKind.exportImages),
          _FileAction('Show file details', _FileActionKind.details),
        ];
      case FileCategory.image:
        return const [
          _FileAction('Convert to another format', _FileActionKind.convert),
          _FileAction('Edit (rotate / compress)', _FileActionKind.editImage),
          _FileAction(
            'Merge into a PDF with other images',
            _FileActionKind.merge,
          ),
          _FileAction('Show file details', _FileActionKind.details),
        ];
      case FileCategory.document:
      case FileCategory.spreadsheet:
      case FileCategory.presentation:
        return const [
          _FileAction('Convert to another format', _FileActionKind.convert),
          _FileAction('Show file details', _FileActionKind.details),
        ];
      default:
        return const [
          _FileAction('Try converting to PDF', _FileActionKind.convert),
          _FileAction('Show file details', _FileActionKind.details),
        ];
    }
  }

  static Future<bool> _promptConvert(
    File file,
    List<String> targets, {
    required String defaultTarget,
  }) async {
    stdout.write(
      '${TerminalUI.style('Target format', TerminalUI.bold)} '
      '(${targets.map((f) => f.toUpperCase()).join(', ')}; '
      'default ${defaultTarget.toUpperCase()}): ',
    );
    final answer =
        (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
    final target = answer.isEmpty ? defaultTarget : answer.replaceAll('.', '');
    final result = await executeConvert(file: file, targetFormat: target);
    return result != null;
  }

  static Future<bool> _promptMerge(File file, {required bool isPdf}) async {
    final noun = isPdf ? 'PDF' : 'image';
    stdout.write(
      '${TerminalUI.style('Add more ${noun}s to merge', TerminalUI.bold)} '
      '(space-separated paths, or drop them here): ',
    );
    final input = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    if (input.isEmpty) return false;

    final extras = _tokenize(input).map((path) => File(path)).toList();
    final missing = extras.where((f) => !f.existsSync()).toList();
    if (missing.isNotEmpty) {
      TerminalUI.error(
        'File not found: "${missing.first.path}"',
        hint: 'Tip: drag & drop the files into this window.',
      );
      return false;
    }

    final imageExtensions = {
      'png',
      'jpg',
      'jpeg',
      'webp',
      'bmp',
      'gif',
      'tiff',
      'ico',
    };
    final files = [file, ...extras];
    final invalid = files.where((f) {
      final ext = FileUtils.getExtension(f.path);
      return isPdf ? ext != 'pdf' : !imageExtensions.contains(ext);
    }).toList();
    if (invalid.isNotEmpty) {
      TerminalUI.error(
        'Cannot merge ${FileUtils.getFileName(invalid.first.path)} into this $noun group.',
        hint: 'Keep all files in the same family (all PDFs or all images).',
      );
      return false;
    }

    return _executeMergeFiles(files);
  }

  static Future<bool> _promptSplit(File file) async {
    stdout.write(
      '${TerminalUI.style('Split every N pages, or a page range', TerminalUI.bold)} '
      '(e.g. 1, 2, or 1-3,5): ',
    );
    final input = (await SlashPrompt.readPlainLine())?.trim() ?? '1';
    if (input.isEmpty) return false;

    try {
      if (input.contains(',') || input.contains('-')) {
        final parts = await PdfEngine.splitExpression(
          sourceFile: file,
          expression: input,
          onProgress: (p) =>
              TerminalUI.printProgressBar(p, label: 'Splitting pages...'),
        );
        await _printParts(parts);
      } else {
        final every = int.tryParse(input) ?? 1;
        final parts = await PdfEngine.splitEvery(
          sourceFile: file,
          every: every,
          onProgress: (p) =>
              TerminalUI.printProgressBar(p, label: 'Splitting pages...'),
        );
        await _printParts(parts);
      }
      return true;
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Split', e);
      return false;
    }
  }

  static Future<bool> _promptCompress(File file) async {
    stdout.write(
      '${TerminalUI.style('Compression level', TerminalUI.bold)} '
      '(screen, ebook, print, lossless; default ebook): ',
    );
    final level = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    try {
      final result = await PdfEngine.compress(
        sourceFile: file,
        level: level.isEmpty ? 'ebook' : level,
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Compressing PDF...'),
      );
      TerminalUI.success('PDF compressed successfully!');
      await _printSavedFiles([result]);
      return true;
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Compress', e);
      return false;
    }
  }

  static Future<bool> _promptWatermark(File file) async {
    stdout.write(
      '${TerminalUI.style('Watermark text', TerminalUI.bold)} (default CONFIDENTIAL): ',
    );
    final text = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    return _executeWatermark(file, text.isEmpty ? 'CONFIDENTIAL' : text);
  }

  static Future<bool> _promptPdfToImages(File file) async {
    stdout.write(
      '${TerminalUI.style('Image format', TerminalUI.bold)} (png or jpg, default png): ',
    );
    final format =
        (await SlashPrompt.readPlainLine())?.trim().toLowerCase() ?? '';
    return _executePdf2Img(file, format.isEmpty ? 'png' : format);
  }

  static Future<bool> _promptEditImage(File file) async {
    stdout.write(
      '${TerminalUI.style('Rotate degrees', TerminalUI.bold)} (0 / 90 / 180 / 270, default 0): ',
    );
    final rotation =
        int.tryParse((await SlashPrompt.readPlainLine())?.trim() ?? '0') ?? 0;
    stdout.write(
      '${TerminalUI.style('Quality', TerminalUI.bold)} (1-100, default 85): ',
    );
    final quality =
        int.tryParse((await SlashPrompt.readPlainLine())?.trim() ?? '85') ?? 85;
    return _executeEdit(file, rotation, quality);
  }

  static void _showFileDetails(File file, List<String> targets) {
    final stat = file.statSync();
    TerminalUI.printBox(
      title: 'File Details',
      lines: [
        '${TerminalUI.style("Path:     ", TerminalUI.gray)}${file.path}',
        '${TerminalUI.style("Size:     ", TerminalUI.gray)}${FileUtils.formatBytes(stat.size)}',
        '${TerminalUI.style("Modified: ", TerminalUI.gray)}${stat.modified}',
        '${TerminalUI.style("Targets:  ", TerminalUI.gray)}${targets.map((f) => f.toUpperCase()).join(", ")}',
      ],
      borderColor: TerminalUI.cyan,
    );
  }

  static Future<void> _parseConvertCommand(String args) async {
    var tokens = _tokenize(args);
    if (tokens.isEmpty) {
      stdout.write(
        '${TerminalUI.style("Source file path (or drag & drop file):", TerminalUI.bold)} ',
      );
      final raw = await SlashPrompt.readPlainLine();
      if (raw == null || raw.trim().isEmpty) return;
      tokens = _tokenize(raw);
    }
    final parsed = _parseArgs(
      tokens,
      valueOptions: {'-o', '--output', '-q', '--quality', '--to', '-t'},
    );
    final paths = parsed.positional;
    if (paths.isEmpty) throw ArgumentError('Provide a source file.');
    final last = paths.last;
    final hasTarget =
        _option(parsed, ['--to', '-t']) != null ||
        !File(last).existsSync() &&
            !Directory(last).existsSync() &&
            RegExp(r'^\.?[A-Za-z0-9]+$').hasMatch(last);
    if (!hasTarget) {
      stdout.write(
        '${TerminalUI.style("Target format (e.g. pdf, png, jpg, csv, txt):", TerminalUI.bold)} ',
      );
      final target = (await SlashPrompt.readPlainLine())?.trim();
      if (target == null || target.isEmpty) return;
      tokens.add(target);
    }
    await handleArguments(tokens, interactive: true);
  }

  /// Batch converts multiple files to a given target format
  static Future<bool> batchConvert(
    List<File> files,
    String targetFormat, {
    bool interactivePostAction = true,
    String? outputDirectory,
    int quality = 85,
  }) async {
    if (outputDirectory != null)
      await Directory(outputDirectory).create(recursive: true);
    TerminalUI.step(
      'Batch converting ${files.length} files to .$targetFormat ...',
    );
    final stopwatch = Stopwatch()..start();
    int successCount = 0;

    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      final res = await executeConvert(
        file: f,
        targetFormat: targetFormat,
        outputPath: outputDirectory,
        quality: quality,
        interactivePostAction: false,
      );
      if (res != null) successCount++;
      TerminalUI.printProgressBar(
        (i + 1) / files.length,
        label: '${i + 1}/${files.length} converted',
      );
    }

    stopwatch.stop();
    TerminalUI.success(
      'Batch conversion complete! $successCount/${files.length} files converted.',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    if (successCount > 0 && interactivePostAction) {
      final outDir = await StorageService().getOutputDirectory();
      await _offerPostAction(outDir);
    }
    if (successCount != files.length) exitCode = 1;
    return successCount == files.length;
  }

  /// Core convert execution shared across CLI & interactive modes
  static Future<File?> executeConvert({
    required File file,
    required String targetFormat,
    String? outputPath,
    int quality = 85,
    bool interactivePostAction = true,
  }) async {
    final ext = FileUtils.getExtension(file.path);

    TerminalUI.step('Converting ${file.path} (.$ext) → .$targetFormat ...');

    final stopwatch = Stopwatch()..start();
    final inBytes = file.lengthSync();
    String engineName = 'Local Conversion Engine';
    File? result;

    try {
      result = await FileOperations.convert(
        sourceFile: file,
        targetFormat: targetFormat,
        outputPath: outputPath,
        quality: quality,
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Processing locally...'),
      );

      stopwatch.stop();

      TerminalUI.printSummaryCard(
        action: 'Convert (.$ext → .$targetFormat)',
        inputPath: file.path,
        inputBytes: inBytes,
        outputPath: result.path,
        outputBytes: result.lengthSync(),
        elapsedMs: stopwatch.elapsedMilliseconds,
        engineName: engineName,
      );

      if (interactivePostAction) {
        await _offerPostConversionAction(result);
      }

      return result;
    } catch (e) {
      exitCode = 1;
      TerminalUI.error('Conversion failed: $e');
      return null;
    }
  }

  static Future<void> _parseMergeCommand(String args) async {
    final tokens = _tokenize(args);
    List<String> filePaths = [];
    String? outPath;

    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i] == '-o' || tokens[i] == '--output') {
        if (i + 1 < tokens.length) {
          outPath = tokens[i + 1];
          i++;
        }
      } else {
        filePaths.add(tokens[i]);
      }
    }

    if (filePaths.length < 2) {
      stdout.write(
        '${TerminalUI.style("Enter files to merge (or drag & drop files here):", TerminalUI.bold)} ',
      );
      final input = (await SlashPrompt.readPlainLine())?.trim() ?? '';
      filePaths = _tokenize(input);
      if (filePaths.length < 2) {
        TerminalUI.error(
          'Merge requires at least two input files.',
          hint:
              'Tip: Drag and drop 2 or more files together into the terminal.',
        );
        return;
      }
    }

    final files = filePaths.map((p) => File(p)).toList();
    for (final f in files) {
      if (!f.existsSync()) {
        final similar = FileUtils.findSimilarFile(f.path);
        TerminalUI.error(
          'File not found: "${f.path}"',
          hint: similar != null
              ? 'Did you mean: "${similar.path}"?'
              : 'Tip: Drag and drop files from Finder/Explorer.',
        );
        return;
      }
    }

    await _executeMergeFiles(files, outputPath: outPath);
  }

  static Future<void> _parseSplitCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {
        '--every',
        '-e',
        '--pages',
        '-p',
        '--size',
        '-s',
        '--output',
        '-o',
      },
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'split');
    if (file == null) return;

    final pagesExpr = _option(parsed, ['--pages', '-p']);
    final sizeRaw = _option(parsed, ['--size', '-s']);
    final everyRaw = _option(parsed, ['--every', '-e']);

    try {
      if (pagesExpr != null) {
        final parts = await PdfEngine.splitExpression(
          sourceFile: file,
          expression: pagesExpr,
          outputDirectory: _option(parsed, ['--output', '-o']),
          onProgress: (p) =>
              TerminalUI.printProgressBar(p, label: 'Splitting pages...'),
        );
        await _printParts(parts);
        return;
      }

      if (sizeRaw != null) {
        final parts = await PdfEngine.splitBySize(
          sourceFile: file,
          maxBytes: _parseBytes(sizeRaw),
          outputDirectory: _option(parsed, ['--output', '-o']),
          onProgress: (p) =>
              TerminalUI.printProgressBar(p, label: 'Measuring parts...'),
        );
        await _printParts(parts);
        return;
      }

      var every = everyRaw == null ? null : int.parse(everyRaw);
      if (every == null) {
        stdout.write(
          '${TerminalUI.style('Pages per part', TerminalUI.bold)} (default 1): ',
        );
        every =
            int.tryParse((await SlashPrompt.readPlainLine())?.trim() ?? '1') ??
            1;
      }

      final parts = await PdfEngine.splitEvery(
        sourceFile: file,
        every: every,
        outputDirectory: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Splitting pages...'),
      );
      await _printParts(parts);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Split', e);
    }
  }

  static Future<void> _parseExtractCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--pages', '-p', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'extract');
    if (file == null) return;

    var pagesExpr = _option(parsed, ['--pages', '-p']);
    if (pagesExpr == null && parsed.positional.length >= 2) {
      pagesExpr = parsed.positional[1];
    }
    if (pagesExpr == null) {
      stdout.write(
        '${TerminalUI.style('Pages to keep', TerminalUI.bold)} (e.g. 1-3,5): ',
      );
      pagesExpr = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    }

    if (pagesExpr.isEmpty) {
      TerminalUI.error('No page selection given.');
      return;
    }

    try {
      final result = await PdfEngine.extractPages(
        sourceFile: file,
        expression: pagesExpr,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Extracting pages...'),
      );
      TerminalUI.success('Pages extracted successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Extract', e);
    }
  }

  static Future<void> _parseOrganizeCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--order', '--delete', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'organize');
    if (file == null) return;

    var order = _option(parsed, ['--order']);
    final delete = _option(parsed, ['--delete']);
    if (order == null && delete == null && parsed.positional.length >= 2) {
      order = parsed.positional[1];
    }

    if (order == null && delete == null) {
      stdout.write(
        '${TerminalUI.style('New page order', TerminalUI.bold)} (e.g. 3,1,2; blank to delete pages): ',
      );
      final input = (await SlashPrompt.readPlainLine())?.trim() ?? '';
      if (input.isEmpty) {
        stdout.write(
          '${TerminalUI.style('Pages to delete', TerminalUI.bold)} (e.g. 2,5): ',
        );
        final removed = (await SlashPrompt.readPlainLine())?.trim() ?? '';
        if (removed.isEmpty) return;
        return _runOrganize(file, delete: removed);
      }
      return _runOrganize(file, order: input);
    }

    await _runOrganize(
      file,
      order: order,
      delete: delete,
      outputPath: _option(parsed, ['--output', '-o']),
    );
  }

  static Future<void> _runOrganize(
    File file, {
    String? order,
    String? delete,
    String? outputPath,
  }) async {
    if (order != null && delete != null) {
      TerminalUI.error('Choose either --order or --delete, not both.');
      return;
    }

    try {
      final result = order != null
          ? await PdfEngine.organize(
              sourceFile: file,
              order: order,
              outputPath: outputPath,
              onProgress: (p) =>
                  TerminalUI.printProgressBar(p, label: 'Reordering pages...'),
            )
          : await PdfEngine.deletePages(
              sourceFile: file,
              expression: delete!,
              outputPath: outputPath,
              onProgress: (p) =>
                  TerminalUI.printProgressBar(p, label: 'Removing pages...'),
            );
      TerminalUI.success('Pages organized successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Organize', e);
    }
  }

  static Future<void> _parseRotateCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--degrees', '-d', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'rotate');
    if (file == null) return;

    var raw = _option(parsed, ['--degrees', '-d']);
    if (raw == null && parsed.positional.length >= 2) {
      raw = parsed.positional[1];
    }
    if (raw == null) {
      stdout.write(
        '${TerminalUI.style('Rotate by', TerminalUI.bold)} (90, 180, 270; default 90): ',
      );
      raw = (await SlashPrompt.readPlainLine())?.trim() ?? '90';
    }

    final degrees = int.tryParse(raw);
    if (degrees == null) {
      exitCode = 1;
      TerminalUI.error('Rotation must be 90, 180, or 270.');
      return;
    }

    try {
      final result = await PdfEngine.rotate(
        sourceFile: file,
        degrees: degrees,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Rotating pages...'),
      );
      TerminalUI.success('PDF rotated successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Rotate', e);
    }
  }

  static Future<void> _parseCompressCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--level', '-l', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'compress');
    if (file == null) return;

    var level = _option(parsed, ['--level', '-l']);
    if (level == null && parsed.positional.length >= 2) {
      level = parsed.positional[1];
    }
    level ??= 'ebook';

    try {
      final result = await PdfEngine.compress(
        sourceFile: file,
        level: level,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Compressing PDF...'),
      );
      TerminalUI.success('PDF compressed successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Compress', e);
    }
  }

  static Future<void> _parseCropCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {
        '--left',
        '--top',
        '--right',
        '--bottom',
        '--output',
        '-o',
      },
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'crop');
    if (file == null) return;

    double value(String name, int positionalIndex) {
      final raw =
          _option(parsed, ['--$name']) ??
          (parsed.positional.length > positionalIndex
              ? parsed.positional[positionalIndex]
              : null);
      return double.parse(raw ?? '0');
    }

    var left = value('left', 1);
    var top = value('top', 2);
    var right = value('right', 3);
    var bottom = value('bottom', 4);

    if (left == 0 && top == 0 && right == 0 && bottom == 0) {
      stdout.write(
        '${TerminalUI.style('Margins in points', TerminalUI.bold)} '
        '(left top right bottom, e.g. 20 20 20 20): ',
      );
      final parts = ((await SlashPrompt.readPlainLine()) ?? '')
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length >= 4) {
        left = double.tryParse(parts[0]) ?? 0;
        top = double.tryParse(parts[1]) ?? 0;
        right = double.tryParse(parts[2]) ?? 0;
        bottom = double.tryParse(parts[3]) ?? 0;
      }
    }

    try {
      final result = await PdfEngine.crop(
        sourceFile: file,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Cropping pages...'),
      );
      TerminalUI.success('PDF cropped successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Crop', e);
    }
  }

  static Future<void> _parsePageNumbersCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'number');
    if (file == null) return;

    try {
      final result = await PdfEngine.pageNumbers(
        sourceFile: file,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Numbering pages...'),
      );
      TerminalUI.success('Page numbers added successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Page numbering', e);
    }
  }

  static Future<void> _parseProtectCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--password', '-p', '--owner', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'protect');
    if (file == null) return;

    var password = _option(parsed, ['--password', '-p']);
    if (password == null) {
      password = await _readSecret(
        '${TerminalUI.style('Password', TerminalUI.bold)} (not stored): ',
      );
      if (password == null || password.isEmpty) {
        TerminalUI.error('A password is required.');
        return;
      }
      final confirm = await _readSecret(
        '${TerminalUI.style('Confirm password', TerminalUI.bold)}: ',
      );
      if (confirm != password) {
        TerminalUI.error('Passwords do not match.');
        return;
      }
    }

    try {
      final result = await PdfEngine.protect(
        sourceFile: file,
        password: password,
        ownerPassword: _option(parsed, ['--owner']),
        outputPath: _option(parsed, ['--output', '-o']),
      );
      TerminalUI.success('PDF protected successfully!');
      stdout.writeln(
        TerminalUI.style(
          '  Keep this password safe: it is never written to disk.',
          TerminalUI.dim,
        ),
      );
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Protect', e);
    }
  }

  static Future<void> _parseUnlockCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--password', '-p', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'unlock');
    if (file == null) return;

    final password =
        _option(parsed, ['--password', '-p']) ??
        await _readSecret(
          '${TerminalUI.style('PDF password', TerminalUI.bold)}: ',
        );
    if (password == null || password.isEmpty) {
      TerminalUI.error('A password is required.');
      return;
    }

    try {
      final result = await PdfEngine.unlock(
        sourceFile: file,
        password: password,
        outputPath: _option(parsed, ['--output', '-o']),
      );
      TerminalUI.success('PDF unlocked successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Unlock', e);
    }
  }

  static Future<void> _parsePdf2TextCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--output', '-o'},
      boolFlags: {'--print'},
    );
    final file = await _requirePdf(
      parsed.positional.firstOrNull,
      'extract text',
    );
    if (file == null) return;

    try {
      final result = await PdfConverter().pdfToText(
        pdfFile: file,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Extracting text...'),
      );
      TerminalUI.success('Text extracted successfully!');
      if (_hasFlag(parsed, '--print')) {
        stdout.writeln();
        stdout.writeln(await result.readAsString());
      }
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Text extraction', e);
    }
  }

  static Future<void> _parsePdf2OfficeCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--to', '-t', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'convert');
    if (file == null) return;

    var format = _option(parsed, ['--to', '-t']);
    if (format == null && parsed.positional.length >= 2) {
      format = parsed.positional[1];
    }
    if (format == null) {
      stdout.write(
        '${TerminalUI.style('Convert to', TerminalUI.bold)} (docx, xlsx, pptx): ',
      );
      format = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    }

    try {
      final result = await PdfEngine.convertToOffice(
        sourceFile: file,
        format: format.replaceAll('.', '').toLowerCase(),
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Building document...'),
      );
      TerminalUI.success('PDF converted to Office successfully!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('PDF to Office', e);
    }
  }

  static Future<void> _parsePdfaCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--level', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'archive');
    if (file == null) return;

    final levelRaw =
        _option(parsed, ['--level']) ??
        (parsed.positional.length >= 2 ? parsed.positional[1] : '2');
    final level = int.parse(levelRaw);
    try {
      final result = await PdfEngine.convertToPdfA(
        sourceFile: file,
        level: level,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Writing PDF/A...'),
      );
      TerminalUI.success('PDF/A conversion complete!');
      await _printSavedFiles([result]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('PDF/A conversion', e);
    }
  }

  static Future<void> _parseRedactCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--text', '-t', '--output', '-o'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'redact');
    if (file == null) return;

    var text = _option(parsed, ['--text', '-t']);
    if (text == null && parsed.positional.length >= 2) {
      text = parsed.positional[1];
    }
    if (text == null) {
      stdout.write(
        '${TerminalUI.style('Text to redact', TerminalUI.bold)} (every match): ',
      );
      text = (await SlashPrompt.readPlainLine())?.trim() ?? '';
    }

    try {
      final result = await PdfEngine.redactText(
        sourceFile: file,
        query: text,
        outputPath: _option(parsed, ['--output', '-o']),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Applying redactions...'),
      );
      TerminalUI.success(
        'Redacted ${result.matches} match${result.matches == 1 ? '' : 'es'} permanently!',
      );
      await _printSavedFiles([result.file]);
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Redaction', e);
    }
  }

  static Future<void> _parseInfoCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--password', '-p'},
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'inspect');
    if (file == null) return;

    try {
      final info = await PdfEngine.info(
        file,
        password: _option(parsed, ['--password', '-p']),
      );
      TerminalUI.printBox(
        title: 'PDF Details',
        lines: [
          '${TerminalUI.style("File:      ", TerminalUI.gray)}${file.path}',
          '${TerminalUI.style("Size:      ", TerminalUI.gray)}${FileUtils.formatBytes(file.lengthSync())}',
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
    } catch (e) {
      exitCode = 1;
      _pdfFailure('Inspect', e);
    }
  }

  static Future<void> _parseWatermarkCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {
        '--text',
        '-w',
        '--opacity',
        '-a',
        '--angle',
        '--output',
        '-o',
      },
    );
    final file = await _requirePdf(parsed.positional.firstOrNull, 'watermark');
    if (file == null) return;
    var text =
        _option(parsed, ['--text', '-w']) ??
        (parsed.positional.length > 1
            ? parsed.positional.skip(1).join(' ')
            : null);
    if (text == null) {
      stdout.write(
        '${TerminalUI.style("Watermark text (e.g. CONFIDENTIAL):", TerminalUI.bold)} ',
      );
      text = await SlashPrompt.readPlainLine();
    }
    if (text == null || text.isEmpty) return;
    await _executeWatermark(
      file,
      text,
      outputPath: _option(parsed, ['--output', '-o']),
      opacity: double.parse(_option(parsed, ['--opacity', '-a']) ?? '0.25'),
      angle: double.parse(_option(parsed, ['--angle']) ?? '-45'),
    );
  }

  static Future<bool> _executeWatermark(
    File file,
    String text, {
    String? outputPath,
    double opacity = 0.25,
    double angle = -45,
  }) async {
    TerminalUI.step('Applying watermark "$text" ...');
    final stopwatch = Stopwatch()..start();
    try {
      final result = await PdfConverter().applyWatermark(
        pdfFile: file,
        watermarkText: text,
        outputPath: outputPath,
        opacity: opacity,
        angle: angle,
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Stamping vector overlay...'),
      );
      stopwatch.stop();

      TerminalUI.success(
        'Watermark applied successfully!',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      await _printSavedFiles([result]);
      return true;
    } catch (e) {
      exitCode = 1;
      TerminalUI.error('Watermark failed: $e');
      return false;
    }
  }

  static Future<void> _parsePdf2ImgCommand(String args) async {
    final parsed = _parseArgs(
      _tokenize(args),
      valueOptions: {'--to', '-t', '--dpi', '--output', '-o'},
    );
    final file = await _requirePdf(
      parsed.positional.firstOrNull,
      'export pages',
    );
    if (file == null) return;

    var fmt =
        _option(parsed, ['--to', '-t']) ??
        (parsed.positional.length >= 2 ? parsed.positional[1] : null);
    if (fmt == null) {
      stdout.write(
        '${TerminalUI.style('Output format', TerminalUI.bold)} (png or jpg, default png): ',
      );
      fmt = (await SlashPrompt.readPlainLine())?.trim() ?? 'png';
    }

    final dpi = int.parse(
      _option(parsed, ['--dpi']) ??
          (parsed.positional.length > 2 ? parsed.positional[2] : '150'),
    );
    final rawOutput = _option(parsed, ['--output', '-o']);
    final outputExt = rawOutput == null
        ? ''
        : FileUtils.getExtension(rawOutput);
    final explicitFile =
        rawOutput != null &&
        !Directory(rawOutput).existsSync() &&
        ['png', 'jpg', 'jpeg'].contains(outputExt);

    await _executePdf2Img(
      file,
      fmt.isEmpty ? 'png' : fmt,
      dpi: dpi,
      outputDirectory: explicitFile ? File(rawOutput).parent.path : rawOutput,
      explicitOutputFile: explicitFile ? rawOutput : null,
    );
  }

  static Future<bool> _executePdf2Img(
    File file,
    String fmt, {
    int dpi = 150,
    String? outputDirectory,
    String? explicitOutputFile,
  }) async {
    TerminalUI.step('Rasterizing PDF pages to .$fmt ($dpi DPI) ...');
    final stopwatch = Stopwatch()..start();
    try {
      final results = await PdfEngine.renderPages(
        sourceFile: file,
        targetFormat: fmt,
        dpi: dpi,
        outputDirectory: outputDirectory,
        firstPageOutputPath: explicitOutputFile,
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Rasterizing pages...'),
      );

      stopwatch.stop();

      TerminalUI.success(
        'Exported ${results.length} page${results.length == 1 ? '' : 's'}!',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      await _printSavedFiles(results);
      return true;
    } catch (e) {
      exitCode = 1;
      TerminalUI.error(
        'PDF rasterization failed: ${PdfEngine.errorMessage(e)}',
        hint:
            'The bundled engine handles this locally; no native tools needed.',
      );
      return false;
    }
  }

  static Future<void> _parseEditCommand(String args) async {
    final tokens = _tokenize(args);
    if (tokens.isEmpty) {
      stdout.write(
        '${TerminalUI.style("Image file path (or drag & drop image):", TerminalUI.bold)} ',
      );
      final rawPath = (await SlashPrompt.readPlainLine())?.trim() ?? '';
      final path = sanitizeToken(rawPath);
      final file = File(path);
      if (!file.existsSync()) {
        final similar = FileUtils.findSimilarFile(path);
        TerminalUI.error(
          'File not found: "$path"',
          hint: similar != null
              ? 'Did you mean: "${similar.path}"?'
              : 'Tip: Drag and drop file.',
        );
        return;
      }
      stdout.write(
        '${TerminalUI.style("Rotate degrees (0, 90, 180, 270):", TerminalUI.bold)} ',
      );
      final rot =
          int.tryParse((await SlashPrompt.readPlainLine())?.trim() ?? '0') ?? 0;
      stdout.write(
        '${TerminalUI.style("Quality (1-100, default 85):", TerminalUI.bold)} ',
      );
      final q =
          int.tryParse((await SlashPrompt.readPlainLine())?.trim() ?? '85') ??
          85;

      await _executeEdit(file, rot, q);
      return;
    }

    final parsed = _parseArgs(
      tokens,
      valueOptions: {
        '--rotate',
        '-r',
        '--quality',
        '-q',
        '--to',
        '-t',
        '--output',
        '-o',
      },
      boolFlags: {'--flip-h', '--flip-v'},
    );
    final file = File(parsed.positional.first);
    if (!file.existsSync()) throw ArgumentError('File not found: ${file.path}');
    await _executeEdit(
      file,
      int.parse(_option(parsed, ['--rotate', '-r']) ?? '0'),
      int.parse(_option(parsed, ['--quality', '-q']) ?? '85'),
      outputPath: _option(parsed, ['--output', '-o']),
      targetFormat: _option(parsed, ['--to', '-t']),
      flipHorizontal: _hasFlag(parsed, '--flip-h'),
      flipVertical: _hasFlag(parsed, '--flip-v'),
    );
  }

  static Future<bool> _executeEdit(
    File file,
    int rot,
    int q, {
    String? outputPath,
    String? targetFormat,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) async {
    TerminalUI.step('Transforming image ${file.path} ...');
    final stopwatch = Stopwatch()..start();
    final ext = FileUtils.getExtension(file.path);

    try {
      final result = await ImageConverter().convert(
        sourceFile: file,
        targetFormat: targetFormat ?? ext,
        outputPath: outputPath,
        imageOptions: ImageEditOptions(
          rotationDegrees: rot,
          flipHorizontal: flipHorizontal,
          flipVertical: flipVertical,
          compressionQuality: q,
        ),
        onProgress: (p) =>
            TerminalUI.printProgressBar(p, label: 'Processing pixels...'),
      );
      stopwatch.stop();

      TerminalUI.success(
        'Image edited successfully!',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      await _printSavedFiles([result]);
      return true;
    } catch (e) {
      exitCode = 1;
      TerminalUI.error('Image edit failed: $e');
      return false;
    }
  }

  static Future<void> _showRecentHistory() async {
    final history = HistoryService().getHistory();
    if (history.isEmpty) {
      stdout.writeln(
        TerminalUI.style(
          'No conversions recorded yet. Convert a file to see it here!',
          TerminalUI.gray,
        ),
      );
      return;
    }

    final lines = <String>[];
    for (final item in history.take(8)) {
      final inName = item.sourceName.padRight(20);
      final size = FileUtils.formatBytes(item.fileSizeBytes);
      lines.add(
        '${TerminalUI.style(inName, TerminalUI.bold)} ${TerminalUI.style("→", TerminalUI.amber)} ${TerminalUI.style(item.targetFormat.toUpperCase(), TerminalUI.cyan)} ${TerminalUI.style("($size)", TerminalUI.gray)}',
      );
    }

    TerminalUI.printBox(
      title: 'Recent Conversions',
      lines: lines,
      borderColor: TerminalUI.green,
    );
  }

  static Future<void> _showFormats() async {
    final caps = await PlatformDetector.detect();

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

  /// Offers instant 1-key actions ([o] Open, [r] Reveal, [Enter] Continue)
  /// Supports File, List<File>, Directory, or path String.
  static Future<void> _offerPostAction(dynamic target) async {
    if (!stdin.hasTerminal) return;

    File? singleFile;
    List<File>? fileList;
    Directory? dir;

    if (target is File) {
      singleFile = target;
    } else if (target is List<File>) {
      if (target.isEmpty) return;
      if (target.length == 1) {
        singleFile = target.first;
      } else {
        fileList = target;
      }
    } else if (target is Directory) {
      dir = target;
    } else if (target is String) {
      if (FileSystemEntity.isDirectorySync(target)) {
        dir = Directory(target);
      } else {
        singleFile = File(target);
      }
    } else {
      return;
    }

    final revealLabel = Platform.isMacOS
        ? 'Reveal in Finder'
        : (Platform.isWindows ? 'Reveal in Explorer' : 'Reveal in folder');

    if (dir != null) {
      stdout.write(
        '  ${TerminalUI.style("[r] $revealLabel", TerminalUI.brightAmber + TerminalUI.bold)}'
        '  ${TerminalUI.style("·", TerminalUI.darkGray)}'
        '  ${TerminalUI.style("[Enter] Continue", TerminalUI.gray)} › ',
      );
    } else if (fileList != null) {
      stdout.write(
        '  ${TerminalUI.style("[o] Open first file", TerminalUI.brightCyan + TerminalUI.bold)}'
        '  ${TerminalUI.style("·", TerminalUI.darkGray)}'
        '  ${TerminalUI.style("[r] $revealLabel", TerminalUI.brightAmber + TerminalUI.bold)}'
        '  ${TerminalUI.style("·", TerminalUI.darkGray)}'
        '  ${TerminalUI.style("[Enter] Continue", TerminalUI.gray)} › ',
      );
    } else if (singleFile != null) {
      stdout.write(
        '  ${TerminalUI.style("[o] Open file", TerminalUI.brightCyan + TerminalUI.bold)}'
        '  ${TerminalUI.style("·", TerminalUI.darkGray)}'
        '  ${TerminalUI.style("[r] $revealLabel", TerminalUI.brightAmber + TerminalUI.bold)}'
        '  ${TerminalUI.style("·", TerminalUI.darkGray)}'
        '  ${TerminalUI.style("[Enter] Continue", TerminalUI.gray)} › ',
      );
    }

    final previousLineMode = stdin.lineMode;
    final previousEchoMode = stdin.echoMode;
    try {
      stdin.lineMode = false;
      stdin.echoMode = false;

      final byte = await SlashPrompt.readByte();
      if (![10, 13, 111, 79, 114, 82].contains(byte)) {
        // A new drop/command belongs to the next prompt. Never eat its first byte.
        SlashPrompt.pushBack(byte);
      }
      // Clear prompt line
      stdout.write('\r\x1B[2K');

      if (dir != null) {
        if (byte == 114 || byte == 82 || byte == 111 || byte == 79) {
          // 'r', 'R', 'o', 'O'
          final ok = await FileUtils.revealInFileManager(dir.path);
          if (ok) {
            TerminalUI.step('Opened folder ${FileUtils.getFileName(dir.path)}');
          }
        }
      } else if (fileList != null) {
        final first = fileList.first;
        if (byte == 111 || byte == 79) {
          // 'o' or 'O'
          final ok = await FileUtils.openFile(first.path);
          if (ok) {
            TerminalUI.step('Opened ${FileUtils.getFileName(first.path)}');
          }
        } else if (byte == 114 || byte == 82) {
          // 'r' or 'R'
          final ok = await FileUtils.revealInFileManager(first.path);
          if (ok) {
            final name = FileUtils.getFileName(first.path);
            final dest = Platform.isMacOS
                ? 'Finder'
                : (Platform.isWindows ? 'Explorer' : 'file manager');
            TerminalUI.step('Revealed $name in $dest');
          }
        }
      } else if (singleFile != null) {
        if (byte == 111 || byte == 79) {
          // 'o' or 'O'
          final ok = await FileUtils.openFile(singleFile.path);
          if (ok) {
            TerminalUI.step('Opened ${FileUtils.getFileName(singleFile.path)}');
          }
        } else if (byte == 114 || byte == 82) {
          // 'r' or 'R'
          final ok = await FileUtils.revealInFileManager(singleFile.path);
          if (ok) {
            final name = FileUtils.getFileName(singleFile.path);
            final dest = Platform.isMacOS
                ? 'Finder'
                : (Platform.isWindows ? 'Explorer' : 'file manager');
            TerminalUI.step('Revealed $name in $dest');
          }
        }
      }
    } catch (_) {
      // Graceful fallback if terminal doesn't support raw mode
    } finally {
      try {
        stdin.lineMode = previousLineMode;
        stdin.echoMode = previousEchoMode;
      } catch (_) {}
    }
  }

  /// Backward-compatible alias
  static Future<void> _offerPostConversionAction(File file) =>
      _offerPostAction(file);

  /// Displays the 6 Core Cornerstones and air-gap verification
  static void showPrivacyVerification() {
    TerminalUI.printBox(
      title: 'Air-Gap & Privacy Verification',
      lines: [
        '${TerminalUI.style("1. On-Device Sandbox: ", TerminalUI.gray)}${TerminalUI.style("● 100% LOCAL PROCESSING", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("2. Cloud / Telemetry:   ", TerminalUI.gray)}${TerminalUI.style("● 0 Bytes Uploaded (Zero Trackers)", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("3. Quotas & Limits:     ", TerminalUI.gray)}${TerminalUI.style("● UNLIMITED (Zero Paywalls/Fees)", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("4. File Size Cap:       ", TerminalUI.gray)}${TerminalUI.style("● NO APP CAP (RAM/Disk Apply)", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("5. Purely Offline:      ", TerminalUI.gray)}${TerminalUI.style("● AIR-GAPPED (No Internet Required)", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("6. Space Footprint:     ", TerminalUI.gray)}${TerminalUI.style("● ~32 MB CORE (Optional Codecs)", TerminalUI.brightGreen + TerminalUI.bold)}',
        '${TerminalUI.style("Storage Location:       ", TerminalUI.gray)}~/Documents/Converto/ (Full Local Ownership)',
        '${TerminalUI.style("License:                ", TerminalUI.gray)}Apache 2.0 Open Source (Auditable)',
      ],
      borderColor: TerminalUI.green,
    );
    stdout.writeln(
      TerminalUI.style(
        '  Tip: You can safely block Converto in Little Snitch or Windows Firewall — conversion needs no cloud services.',
        TerminalUI.dim,
      ),
    );
  }

  static Future<File?> _requirePdf(String? rawPath, String action) async {
    var path = rawPath != null ? sanitizeToken(rawPath) : '';
    if (path.isEmpty) {
      stdout.write(
        '${TerminalUI.style('PDF file path (or drag & drop PDF):', TerminalUI.bold)} ',
      );
      final read = (await SlashPrompt.readPlainLine())?.trim() ?? '';
      path = sanitizeToken(read);
    }
    if (path.isEmpty) {
      exitCode = 1;
      TerminalUI.error('No file given for $action.');
      return null;
    }

    final file = File(path);
    if (!file.existsSync()) {
      final similar = FileUtils.findSimilarFile(path);
      exitCode = 1;
      TerminalUI.error(
        'File not found: "$path"',
        hint: similar != null
            ? 'Did you mean: "${similar.path}"?'
            : 'Tip: drag and drop the PDF into this window.',
      );
      return null;
    }
    if (FileUtils.getExtension(file.path) != 'pdf') {
      exitCode = 1;
      TerminalUI.error(
        'That is not a PDF file.',
        hint: 'This tool only works on .pdf files.',
      );
      return null;
    }
    return file;
  }

  static _ParsedArgs _parseArgs(
    List<String> tokens, {
    Set<String> valueOptions = const {},
    Set<String> boolFlags = const {},
  }) {
    final positional = <String>[];
    final options = <String, String>{};
    final flags = <String>{};

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '--') {
        positional.addAll(tokens.skip(i + 1));
        break;
      }

      if (token.contains('=') && token.startsWith('--')) {
        final split = token.indexOf('=');
        final key = token.substring(0, split);
        final value = token.substring(split + 1);
        if (valueOptions.contains(key)) {
          options[key] = value;
        } else if (boolFlags.contains(key)) {
          flags.add(key);
        } else {
          throw FormatException('Unknown option $key.');
        }
        continue;
      }

      if (valueOptions.contains(token)) {
        if (i + 1 < tokens.length) {
          options[token] = tokens[++i];
        } else {
          throw FormatException('Missing value for $token.');
        }
        continue;
      }

      if (boolFlags.contains(token)) {
        flags.add(token);
        continue;
      }
      if (token.startsWith('-'))
        throw FormatException('Unknown option $token.');

      positional.add(token);
    }

    return _ParsedArgs(positional: positional, options: options, flags: flags);
  }

  static String? _option(_ParsedArgs args, List<String> names) {
    for (final name in names) {
      final value = args.options[name];
      if (value != null) return value;
    }
    return null;
  }

  static bool _hasFlag(_ParsedArgs args, String name) =>
      args.flags.contains(name) || args.options.containsKey(name);

  static Future<String?> _readSecret(String label) async {
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

  static int _parseBytes(String raw) {
    final match = RegExp(
      r'^\s*([0-9]+(?:\.[0-9]+)?)\s*(b|kb|mb|gb)?\s*$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      throw FormatException('Use a size such as 500KB, 5MB, or 1GB.');
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

  static Future<void> _printSavedFiles(List<File> files) async {
    for (final file in files) {
      stdout.writeln(
        '  ${TerminalUI.style('Saved:', TerminalUI.gray)} ${file.path} '
        '(${FileUtils.formatBytes(file.lengthSync())})',
      );
    }
    if (files.isNotEmpty) {
      await _offerPostAction(files);
    }
  }

  static Future<void> _printParts(List<File> parts) async {
    TerminalUI.success(
      'Split into ${parts.length} PDF${parts.length == 1 ? '' : 's'}!',
    );
    await _printSavedFiles(parts);
  }

  static void _pdfFailure(String action, Object error) {
    exitCode = 1;
    TerminalUI.error('$action failed: ${PdfEngine.errorMessage(error)}');
  }

  /// Robust tokenization of user input and Finder/Explorer/Nautilus drag-and-drop paths.
  /// Seamlessly supports:
  /// - Windows paths (C:\Users\..., "C:\Users\...", trailing backslashes)
  /// - macOS paths (/Users/.../My\ File.pdf, quoted paths)
  /// - Linux XDND file:// URIs and URL-encoded (%20) paths
  /// - PowerShell & prefixes (& "...", &'...')
  /// - Multiple drag-and-drop files (space or newline delimited)
  /// - Single and double quotes
  static List<String> tokenize(String input) =>
      TerminalInputParser.tokenize(input);
  static List<String> _tokenize(String input) => tokenize(input);
  static String sanitizeToken(String raw) =>
      TerminalInputParser.sanitizeToken(raw);
}

enum _FileActionKind {
  convert,
  merge,
  split,
  compress,
  watermark,
  exportImages,
  editImage,
  details,
}

class _FileAction {
  final String label;
  final _FileActionKind kind;

  const _FileAction(this.label, this.kind);
}

class _ParsedArgs {
  const _ParsedArgs({
    required this.positional,
    required this.options,
    required this.flags,
  });

  final List<String> positional;
  final Map<String, String> options;
  final Set<String> flags;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
