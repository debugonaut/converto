import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../../models/scan_options.dart';
import '../../models/gui/file_preview.dart';
import '../../services/gui/local_preview_service.dart';
import '../../services/gui/mobile_documents.dart';
import '../../services/gui/output_names.dart';
import '../../services/gui/workspace_validation.dart';
import '../../services/pdf/pdf_engine.dart';
import '../../services/gui/tool_capabilities.dart';
import '../../services/gui/secondary_file_picker.dart';
import '../widgets/file_preview_view.dart';
import '../widgets/output_name_field.dart';
import '../widgets/workspace_file_list.dart';
import '../widgets/workspace_results.dart';
import '../widgets/pdf_page_controls.dart';
import '../widgets/crop_overlay.dart';
import '../widgets/image_edit_preview.dart';
import '../widgets/scan_preview.dart';
import '../widgets/extended_pdf_options.dart';
import '../widgets/pdf_stamp_preview.dart';
import '../../models/gui/tool_definition.dart';
import '../../services/gui/gui_executor.dart';
import '../../services/gui/gui_job_controller.dart';
import '../tool_icons.dart';

class ToolWorkspace extends StatefulWidget {
  final ToolDefinition tool;
  final List<String> paths;
  final GuiJobController job;
  final String? outputDirectory;
  final bool remember;
  final bool addingFiles;
  final int intakeRevision;
  final LocalPreviewService? previews;
  final ToolCapabilities? capabilities;
  final Future<PickedLocalFile?> Function(List<String>)? secondaryPicker;
  final void Function(ToolDefinition, List<String>)? onUseResults;
  final VoidCallback onBack;
  final Future<void> Function() onPick;
  final Future<void> Function() onChooseOutput;
  final ValueChanged<List<String>> onPathsChanged;
  final Future<void> Function(String, {bool reveal}) onOpen;
  const ToolWorkspace({
    super.key,
    required this.tool,
    required this.paths,
    required this.job,
    required this.outputDirectory,
    required this.remember,
    this.addingFiles = false,
    this.intakeRevision = 0,
    this.previews,
    this.capabilities,
    this.secondaryPicker,
    this.onUseResults,
    required this.onBack,
    required this.onPick,
    required this.onChooseOutput,
    required this.onPathsChanged,
    required this.onOpen,
  });
  @override
  State<ToolWorkspace> createState() => _ToolWorkspaceState();
}

class _ToolWorkspaceState extends State<ToolWorkspace> {
  final _values = <String, Object>{};
  final _fields = <String, TextEditingController>{};
  bool _advancedCrop = false;
  bool _showScanOriginal = false;
  late final LocalPreviewService _previews;
  final _names = <String, TextEditingController>{};
  final _metadata = <String, FilePreview>{};
  final _touched = <String>{};
  late final TextEditingController _combinedName;
  final _scroll = ScrollController();
  String? _activePath;
  bool _resetting = false;
  int _previewRevision = 0;
  ToolCapabilities? _capabilities;
  final _secondary = <String, PickedLocalFile>{};
  bool _pickingSecondary = false;
  int get _reloadToken => _previewRevision + widget.intakeRevision;

  @override
  void initState() {
    super.initState();
    _previews = widget.previews ?? LocalPreviewService();
    _capabilities = widget.capabilities;
    if (_capabilities == null) unawaited(_loadCapabilities());
    _activePath = widget.paths.firstOrNull;
    _combinedName = TextEditingController(
      text: _id == ToolId.merge
          ? 'merged'
          : _id == ToolId.compare
          ? 'comparison'
          : _id == ToolId.scanPdf
          ? 'scanned'
          : 'combined',
    )..addListener(_formChanged);
    widget.job.addListener(_jobChanged);
  }

  Future<void> _loadCapabilities() async {
    final result = await ToolCapabilities.detect(
      mobile: MobileDocuments.enabled,
    );
    if (mounted) setState(() => _capabilities = result);
  }

  String? get _capabilityReason {
    final capabilities =
        _capabilities ??
        (MobileDocuments.enabled
            ? const ToolCapabilities(
                mobile: true,
                libreOffice: false,
                webp: false,
                tesseract: false,
              )
            : null);
    if (capabilities == null) {
      const bundled = ToolCapabilities(
        mobile: false,
        libreOffice: false,
        webp: false,
        tesseract: false,
      );
      return bundled.check(_id, widget.paths.map(FileUtils.getExtension), {
                ..._optionsMap,
                'format': _format,
              }) ==
              null
          ? null
          : 'Checking the installed local capability…';
    }
    return capabilities.check(_id, widget.paths.map(FileUtils.getExtension), {
      ..._optionsMap,
      'format': _format,
    });
  }

  Future<void> _releaseSecondary(String key) async {
    final selection = _secondary.remove(key);
    try {
      await selection?.release();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The temporary imported copy could not be removed.'),
          ),
        );
    }
  }

  Future<void> _pickSecondary(String key, List<String> extensions) async {
    if (_filesLocked || _pickingSecondary) return;
    setState(() => _pickingSecondary = true);
    try {
      final picked = await (widget.secondaryPicker ?? SecondaryFilePicker.pick)(
        extensions,
      );
      if (!mounted) {
        await picked?.release();
        return;
      }
      if (picked == null) return;
      await _releaseSecondary(key);
      if (!mounted) {
        await picked.release();
        return;
      }
      setState(() {
        _secondary[key] = picked;
        _values[key] = picked.path;
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Choose one local ${extensions.join(' or ').toUpperCase()} file.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _pickingSecondary = false);
    }
  }

  void _jobChanged() {
    _previews.paused = _busy;
    if (mounted) setState(() {});
  }

  void _formChanged() {
    if (mounted && !_resetting) setState(() {});
  }

  TextEditingController _name(String path) => _names.putIfAbsent(
    path,
    () =>
        TextEditingController(text: _defaultName(path))
          ..addListener(_formChanged),
  );
  String _defaultName(String path) {
    var base =
        FileUtils.sanitizeFileName(FileUtils.getBaseNameWithoutExtension(path))
            .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '_')
            .replaceAll(RegExp(r'[. ]+$'), '');
    if (base.isEmpty) base = 'file';
    final suffix = switch (_id) {
      ToolId.convert || ToolId.pdfOffice => 'converted',
      ToolId.editImage => 'edited',
      ToolId.scanPdf => 'scanned',
      ToolId.pdfText => 'text',
      ToolId.extract => 'extracted',
      ToolId.organize => 'organized',
      ToolId.rotate => 'rotated',
      ToolId.watermark => 'watermarked',
      ToolId.pageNumbers => 'numbered',
      ToolId.crop => 'cropped',
      ToolId.compress => 'compressed',
      ToolId.protect => 'protected',
      ToolId.redact => 'redacted',
      ToolId.pdfa => 'archival',
      ToolId.unlock => 'unlocked',
      ToolId.repair => 'repaired',
      ToolId.clean => 'cleaned',
      ToolId.sign => 'signed',
      ToolId.flatten => 'flattened',
      ToolId.ocr => 'ocr',
      ToolId.split => 'part',
      _ => '',
    };
    return suffix.isEmpty ? base : '${base}_$suffix';
  }

  String get _extension => _id == ToolId.pdfText
      ? 'txt'
      : _id == ToolId.compare
      ? 'html'
      : _id == ToolId.ocr
      ? _format
      : _id == ToolId.pdfImages && _values['imageMode'] == 'extract'
      ? 'jpg / png'
      : [
          ToolId.convert,
          ToolId.editImage,
          ToolId.pdfImages,
          ToolId.pdfOffice,
        ].contains(_id)
      ? _format
      : 'pdf';
  Map<String, Object> get _optionsMap => {
    'quality': '85',
    'every': '1',
    'dpi': _id == ToolId.ocr ? '300' : '150',
    'language': 'eng',
    'startNumber': '1',
    'margin': '20',
    'imageWidthPercent': '25',
    'maxSizeMb': '10',
    'opacity': '0.25',
    'angle': '45',
    'fontSize': '54',
    'left': '0',
    'top': '0',
    'right': '0',
    'bottom': '0',
    ..._values,
    for (final field in _fields.entries) field.key: field.value.text,
  };
  Map<String, String> get _errors => WorkspaceValidation.check(
    _id,
    _optionsMap,
    preview: _metadata[_activePath],
  );
  bool get _namesValid =>
      _id == ToolId.info ||
      (_combinedOutput
          ? OutputNames.fieldError(_combinedName.text, _extension) == null
          : widget.paths.every(
              (path) =>
                  OutputNames.fieldError(_name(path).text, _extension) == null,
            ));
  void _metadataReady(FilePreview data) {
    if (!mounted || !widget.paths.contains(data.path)) return;
    final old = _metadata[data.path];
    if (old?.kind == data.kind &&
        old?.pageCount == data.pageCount &&
        old?.width == data.width &&
        old?.height == data.height &&
        old?.sizeBytes == data.sizeBytes)
      return;
    setState(
      () => _metadata[data.path] = FilePreview(
        path: data.path,
        kind: data.kind,
        sizeBytes: data.sizeBytes,
        pageCount: data.pageCount,
        width: data.width,
        height: data.height,
        encrypted: data.encrypted,
      ),
    );
    if (_id == ToolId.organize &&
        data.path == _activePath &&
        _controller('pages', '').text.isEmpty &&
        data.kind == 'pdf') {
      _controller('pages', '').text = List.generate(
        data.pageCount,
        (i) => '${i + 1}',
      ).join(',');
    }
  }

  void _resetOptions() {
    for (final key in _secondary.keys.toList()) {
      unawaited(_releaseSecondary(key));
    }
    _resetting = true;
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    _values.clear();
    _touched.clear();
    _advancedCrop = false;
    _showScanOriginal = false;
    _resetting = false;
    final meta = _metadata[_activePath];
    if (_id == ToolId.organize && meta?.kind == 'pdf')
      _controller('pages', '').text = List.generate(
        meta!.pageCount,
        (i) => '${i + 1}',
      ).join(',');
    setState(() {});
  }

  ToolId get _id => widget.tool.id;
  bool get _busy => widget.job.busy;
  bool get _filesLocked => _busy || widget.addingFiles || _pickingSecondary;
  bool get _canCombineImagesToPdf => widget.tool.canCombineImagesToPdf(
    widget.paths.map(FileUtils.getExtension),
    _format,
  );
  bool get _combineImages =>
      _canCombineImagesToPdf && _values['pdfOutput'] != 'separate';
  bool get _combinedOutput =>
      _id == ToolId.merge ||
      _id == ToolId.compare ||
      _combineImages ||
      (_id == ToolId.scanPdf && widget.paths.length > 1);

  List<String> get _targets =>
      widget.tool.targets(widget.paths.map(FileUtils.getExtension));
  String get _format {
    if (_values['format'] case final String selected) return selected;
    if (_id == ToolId.editImage) {
      final original = widget.paths.firstOrNull == null
          ? 'png'
          : FileUtils.getExtension(widget.paths.first);
      if (_targets.contains(original)) return original;
      if (_targets.contains('png')) return 'png';
    }
    return _targets.firstOrNull ?? 'pdf';
  }

  @override
  void didUpdateWidget(covariant ToolWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.capabilities != oldWidget.capabilities)
      _capabilities = widget.capabilities;
    if (!_targets.contains(_format)) _values.remove('format');
    if (!widget.paths.contains(_activePath))
      _activePath = widget.paths.firstOrNull;
    _metadata.removeWhere((path, _) => !widget.paths.contains(path));
    final removed = _names.keys
        .where((path) => !widget.paths.contains(path))
        .toList();
    for (final path in removed) {
      _names.remove(path)?.dispose();
    }
    if (oldWidget.job != widget.job) {
      oldWidget.job.removeListener(_jobChanged);
      widget.job.addListener(_jobChanged);
    }
  }

  @override
  void dispose() {
    for (final selection in _secondary.values) {
      unawaited(selection.release().catchError((_) {}));
    }
    _secondary.clear();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final controller in _names.values) {
      controller.dispose();
    }
    _combinedName.dispose();
    _scroll.dispose();
    widget.job.removeListener(_jobChanged);
    if (widget.previews == null) _previews.dispose();
    super.dispose();
  }

  TextEditingController _controller(String name, String initial) =>
      _fields.putIfAbsent(
        name,
        () => TextEditingController(text: initial)..addListener(_formChanged),
      );
  Widget _field(
    String name,
    String label, {
    String initial = '',
    String? hint,
    bool secret = false,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextField(
      controller: _controller(name, initial),
      enabled: !_filesLocked,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      onChanged: (value) {
        _touched.add(name);
        _values[name] = value;
        if (name == 'pages' && _id == ToolId.organize)
          _values.remove('pageRotations');
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: _touched.contains(name) ? _errors[name] : null,
        helperText: help,
        helperMaxLines: 3,
      ),
    ),
  );
  Widget _choice(
    String name,
    String label,
    Map<String, String> choices,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      key: ValueKey(
        '$name-${_values[name] ?? fallback}-${choices.keys.join()}',
      ),
      initialValue: choices.containsKey(_values[name] ?? fallback)
          ? '${_values[name] ?? fallback}'
          : choices.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: _filesLocked
          ? null
          : (value) => setState(() => _values[name] = value!),
    ),
  );
  Future<void> _run() async {
    if (widget.outputDirectory == null ||
        _filesLocked ||
        _errors.isNotEmpty ||
        !_namesValid)
      return;
    if (_id == ToolId.compare && widget.paths.length != 2) return;
    if (_capabilityReason != null) return;
    FocusScope.of(context).unfocus();
    final options = <String, Object>{..._values};
    for (final entry in _fields.entries) {
      options[entry.key] = entry.value.text;
    }
    options['format'] = _format;
    if (_id == ToolId.split && options['splitMode'] == 'count')
      options.remove('pages');
    if (_id == ToolId.protect &&
        options['password'] != options['confirmPassword']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The passwords do not match.')),
      );
      return;
    }
    options.remove('confirmPassword');
    await widget.job.run(
      GuiRequest(
        tool: _id,
        paths: List.of(widget.paths),
        outputDirectory: widget.outputDirectory!,
        options: options,
        outputName: _id == ToolId.info
            ? null
            : _combinedOutput
            ? _combinedName.text
            : widget.paths.length == 1
            ? _name(widget.paths.single).text
            : null,
        outputNames:
            _combinedOutput || _id == ToolId.info || widget.paths.length < 2
            ? const {}
            : {for (final path in widget.paths) path: _name(path).text},
      ),
      remember: widget.remember,
    );
    for (final key in [
      'password',
      'confirmPassword',
      'certificatePassword',
      'leftPassword',
      'rightPassword',
    ]) {
      _fields[key]?.clear();
      _values.remove(key);
    }
    _values.remove('certificatePath');
    await _releaseSecondary('certificatePath');
    if (mounted) {
      setState(() {});
      if (widget.job.result != null)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients)
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final incompatible = widget.paths
        .where((path) => !widget.tool.accepts(FileUtils.getExtension(path)))
        .length;
    final errors = _errors;
    final valid =
        !_filesLocked &&
        widget.paths.isNotEmpty &&
        incompatible == 0 &&
        _targets.isNotEmpty &&
        (_id != ToolId.merge || widget.paths.length >= 2) &&
        (_id != ToolId.compare || widget.paths.length == 2) &&
        _capabilityReason == null &&
        widget.outputDirectory != null &&
        errors.isEmpty &&
        _namesValid;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              20,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              28,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : widget.onBack,
                          icon: const Icon(Icons.arrow_back, size: 17),
                          label: const Text('All tools'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _resetOptions,
                          icon: const Icon(Icons.restart_alt, size: 17),
                          label: const Text('Reset options'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(toolIcon(_id), size: 28, color: AppTheme.amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.tool.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.tool.description,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 22),
                    if (_capabilityReason case final String reason)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          reason,
                          style: const TextStyle(color: AppTheme.amber),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final deferPreview =
                            box.maxWidth < 820 &&
                            [
                              ToolId.compare,
                              ToolId.repair,
                              ToolId.clean,
                              ToolId.sign,
                              ToolId.ocr,
                              ToolId.flatten,
                            ].contains(_id);
                        final files = _files(
                          incompatible,
                          showPreview: !deferPreview,
                        );
                        final options = _id == ToolId.merge
                            ? (_activePath == null
                                  ? const SizedBox.shrink()
                                  : _sourcePreview(
                                      _activePath!,
                                      _metadata[_activePath],
                                    ))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _options(),
                                  if (errors.isNotEmpty &&
                                      widget.paths.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        errors.values.first,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ),
                                  if (widget.paths.length > 1 &&
                                      !_combinedOutput)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 18),
                                      child: Text(
                                        'Options apply to each selected file.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                        if (box.maxWidth < 820)
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              files,
                              const SizedBox(height: 25),
                              options,
                              if (deferPreview && _activePath != null)
                                _sourcePreview(
                                  _activePath!,
                                  _metadata[_activePath],
                                ),
                            ],
                          );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: files),
                            const SizedBox(width: 32),
                            Expanded(flex: 5, child: options),
                          ],
                        );
                      },
                    ),
                    if (widget.job.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                '${widget.job.error}\nNo output files were saved. Adjust the selection or options and try again.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_busy && widget.job.message.startsWith('Cancelled'))
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Text(
                          widget.job.message,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    if (widget.job.result != null && !_busy) ...[
                      const SizedBox(height: 26),
                      const Divider(),
                      const SizedBox(height: 22),
                      if (widget.job.historyWarning != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            widget.job.historyWarning!,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                        ),
                      WorkspaceResults(
                        result: widget.job.result!,
                        tool: _id,
                        previews: _previews,
                        onOpen: widget.onOpen,
                        onContinue: widget.onUseResults,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        _exportBar(valid),
      ],
    );
  }

  Widget _exportBar(bool valid) => Container(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      13,
      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
      12,
    ),
    decoration: const BoxDecoration(
      color: AppTheme.background,
      border: Border(top: BorderSide(color: AppTheme.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_id != ToolId.info &&
            (_combinedOutput || widget.paths.length == 1)) ...[
          OutputNameField(
            controller: _combinedOutput
                ? _combinedName
                : _name(widget.paths.single),
            extension: _extension,
            enabled: !_filesLocked,
            numbered:
                _id == ToolId.split ||
                _id == ToolId.pdfImages ||
                (_id == ToolId.convert &&
                    widget.paths.any(
                      (path) => FileUtils.getExtension(path) == 'pdf',
                    ) &&
                    ['png', 'jpg', 'jpeg'].contains(_format)),
          ),
          const SizedBox(height: 10),
        ],
        _actionControls(valid),
        if (_busy) ...[
          const SizedBox(height: 11),
          LinearProgressIndicator(
            value: widget.job.progress > 0 ? widget.job.progress : null,
            minHeight: 3,
            backgroundColor: AppTheme.border,
          ),
          const SizedBox(height: 6),
          Text(
            widget.job.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      ],
    ),
  );

  Widget _actionControls(bool valid) => LayoutBuilder(
    builder: (context, box) {
      Widget folder() => MobileDocuments.enabled
          ? const Text(
              'Saved in this app · export a copy after processing',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            )
          : Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 17,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: widget.outputDirectory ?? '',
                    child: Text(
                      widget.outputDirectory == null
                          ? 'Loading output folder…'
                          : p.basename(widget.outputDirectory!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: MediaQuery.textScalerOf(context).scale(14) > 20 ? 2 : 0,
                  child: TextButton(
                    onPressed: _busy ? null : widget.onChooseOutput,
                    child: const Text('Change folder'),
                  ),
                ),
              ],
            );
      Widget button() => FilledButton.icon(
        key: const Key('run-tool'),
        onPressed: valid && !_busy ? _run : null,
        icon: Icon(
          _id == ToolId.info ? Icons.info_outline : Icons.play_arrow_rounded,
          size: 18,
        ),
        label: Text(
          _busy
              ? 'Processing…'
              : widget.addingFiles
              ? 'Adding files…'
              : _id == ToolId.info
              ? 'Inspect files'
              : 'Run ${widget.tool.title.toLowerCase()}',
        ),
      );
      Widget cancel() => TextButton(
        onPressed: widget.job.cancelling ? null : widget.job.cancel,
        child: const Text('Cancel'),
      );
      final stacked =
          box.maxWidth < 620 || MediaQuery.textScalerOf(context).scale(14) > 20;
      if (stacked)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_id != ToolId.info) folder(),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_busy) cancel(),
                Expanded(child: button()),
              ],
            ),
          ],
        );
      return Row(
        children: [
          if (_id != ToolId.info) Expanded(child: folder()) else const Spacer(),
          if (_busy) cancel(),
          const SizedBox(width: 12),
          button(),
        ],
      );
    },
  );

  Widget _files(int incompatible, {bool showPreview = true}) {
    final active = _activePath;
    final meta = _metadata[active];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Files${widget.paths.isEmpty ? '' : ' · ${widget.paths.length}'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (widget.paths.isNotEmpty)
              TextButton(
                onPressed: _filesLocked
                    ? null
                    : () => widget.onPathsChanged([]),
                child: const Text('Clear'),
              ),
            TextButton.icon(
              onPressed: _filesLocked ? null : widget.onPick,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Add files'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.paths.isEmpty)
          Container(
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              onTap: _filesLocked ? null : widget.onPick,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.file_download_outlined,
                    color: AppTheme.muted,
                    size: 30,
                  ),
                  SizedBox(height: 14),
                  Text(
                    MobileDocuments.enabled
                        ? 'Tap to choose files'
                        : 'Drop files here or choose files',
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Nothing is saved until you run the tool.',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ),
        if (widget.paths.isNotEmpty)
          WorkspaceFileList(
            tool: widget.tool,
            paths: widget.paths,
            service: _previews,
            metadata: _metadata,
            reloadToken: _reloadToken,
            locked: _filesLocked,
            combinedOutput: _combinedOutput,
            extension: _extension,
            activePath: active,
            failedPath: widget.job.failedSource,
            nameController: _name,
            onChanged: widget.onPathsChanged,
            onMetadata: _metadataReady,
            onPreview: (path) => setState(() => _activePath = path),
          ),
        if (incompatible > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Remove $incompatible incompatible files to continue.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_combinedOutput)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              MobileDocuments.enabled
                  ? 'Use each file’s menu to change its order or remove it.'
                  : 'Drag the handles to arrange files. Arrow buttons also move files.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
        if (showPreview && active != null && _id != ToolId.merge)
          _sourcePreview(active, meta),
      ],
    );
  }

  Widget _sourcePreview(String active, FilePreview? meta) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Text(
              'Preview · ${p.basename(active)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
          IconButton(
            tooltip: 'Refresh preview',
            onPressed: _filesLocked
                ? null
                : () => setState(() {
                    _previews.clear();
                    _metadata.clear();
                    _previewRevision++;
                  }),
            icon: const Icon(Icons.refresh, size: 17),
          ),
          IconButton(
            tooltip: 'Expand preview',
            onPressed: () => showLocalPreview(
              context,
              active,
              _previews,
              openOriginal: (path) => widget.onOpen(path),
              imageBuilder: _id == ToolId.scanPdf ? _editPreview : null,
            ),
            icon: const Icon(Icons.open_in_full, size: 17),
          ),
        ],
      ),
      Container(
        height: _id == ToolId.merge ? 340 : 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FilePreviewView(
          key: ValueKey(active),
          path: active,
          service: _previews,
          onMetadata: _metadataReady,
          imageBuilder: _editPreview,
          reloadToken: _reloadToken,
        ),
      ),
      if (meta?.kind == 'pdf' &&
          [ToolId.organize, ToolId.extract, ToolId.split].contains(_id))
        PdfPageControls(
          key: ValueKey('pages-$active-${_id.name}-$_reloadToken'),
          path: active,
          pageCount: meta!.pageCount,
          service: _previews,
          expression: _controller('pages', ''),
          organize: _id == ToolId.organize,
          rotations: (_values['pageRotations'] as List<int>?) ?? const [],
          selectable: _id == ToolId.extract,
          enabled: !_filesLocked,
          onRotations: (rotations) =>
              setState(() => _values['pageRotations'] = rotations),
          onInspectPage: (page) => showLocalPreview(
            context,
            active,
            _previews,
            initialPage: page,
            openOriginal: (path) => widget.onOpen(path),
          ),
        ),
    ],
  );

  int? _optionalInt(String name) => int.tryParse(_fields[name]?.text ?? '');
  ImageEditOptions get _imageOptions => ImageEditOptions(
    rotationDegrees: int.tryParse('${_values['degrees'] ?? 0}') ?? 0,
    flipHorizontal: _values['flipHorizontal'] == true,
    flipVertical: _values['flipVertical'] == true,
    targetWidth: _optionalInt('width'),
    targetHeight: _optionalInt('height'),
    cropX: _optionalInt('cropX'),
    cropY: _optionalInt('cropY'),
    cropWidth: _optionalInt('cropWidth'),
    cropHeight: _optionalInt('cropHeight'),
  );

  Widget _editPreview(FilePreview data, Widget image) {
    if (_id == ToolId.watermark &&
        data.kind == 'pdf' &&
        _errors.isEmpty &&
        (_values['watermarkKind'] == 'image'
            ? _values['watermarkImage'] != null
            : (_fields['text']?.text.isNotEmpty ?? false))) {
      final scope = _fields['pages']?.text.trim() ?? '';
      if (scope.isNotEmpty &&
          !PdfEngine.parsePageList(scope, data.pageCount).contains(data.page))
        return image;
      return PdfStampPreview(
        key: ValueKey('stamp-${data.path}'),
        source: data.path,
        page: data.page,
        options: _optionsMap,
        original: image,
        enabled: !_busy,
      );
    }
    if (_id == ToolId.scanPdf && !_showScanOriginal) {
      return ScanPreview(
        image: data.image!,
        options: ScanOptions.fromMap(_optionsMap),
      );
    }
    if (_id == ToolId.editImage && data.kind == 'image')
      return ImageEditPreview(
        source: data,
        options: _imageOptions,
        selectingCrop: _advancedCrop,
        enabled: !_filesLocked,
        onCrop: (rect) {
          final swapped = _imageOptions.rotationDegrees % 180 != 0;
          final width = swapped ? data.height : data.width,
              height = swapped ? data.width : data.height;
          _resetting = true;
          _controller('cropX', '').text = '${(rect.left * width).round()}';
          _controller('cropY', '').text = '${(rect.top * height).round()}';
          _controller('cropWidth', '').text =
              '${math.max(1, (rect.width * width).round())}';
          _controller('cropHeight', '').text =
              '${math.max(1, (rect.height * height).round())}';
          _resetting = false;
          setState(() {});
        },
      );
    if (_id == ToolId.rotate)
      return RotatedBox(
        quarterTurns: (int.tryParse('${_values['degrees'] ?? 90}') ?? 90) ~/ 90,
        child: image,
      );
    if (_id == ToolId.crop && data.width > 0 && data.height > 0) {
      double margin(String name) =>
          double.tryParse(_fields[name]?.text ?? '') ?? 0;
      final rect = Rect.fromLTRB(
        (margin('left') / data.width).clamp(0, .99),
        (margin('top') / data.height).clamp(0, .99),
        (1 - margin('right') / data.width).clamp(.01, 1),
        (1 - margin('bottom') / data.height).clamp(.01, 1),
      );
      if (rect.width <= 0 || rect.height <= 0) return image;
      return Center(
        child: AspectRatio(
          aspectRatio: data.width / data.height,
          child: CropOverlay(
            rectangle: rect,
            enabled: !_filesLocked,
            onChanged: (value) {
              _resetting = true;
              _controller('left', '0').text = (value.left * data.width)
                  .toStringAsFixed(1);
              _controller('top', '0').text = (value.top * data.height)
                  .toStringAsFixed(1);
              _controller('right', '0').text = ((1 - value.right) * data.width)
                  .toStringAsFixed(1);
              _controller('bottom', '0').text =
                  ((1 - value.bottom) * data.height).toStringAsFixed(1);
              _resetting = false;
              setState(() {});
            },
            child: image,
          ),
        ),
      );
    }
    if (_id == ToolId.watermark && data.width > 0) {
      final text = _fields['text']?.text ?? '';
      if (text.isNotEmpty)
        return Center(
          child: AspectRatio(
            aspectRatio: data.width / data.height,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  Center(
                    child: Transform.rotate(
                      angle:
                          -(double.tryParse(_fields['angle']?.text ?? '45') ??
                              45) *
                          math.pi /
                          180,
                      child: Text(
                        text,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize:
                              (double.tryParse(
                                        _fields['fontSize']?.text ?? '54',
                                      ) ??
                                      54)
                                  .clamp(.1, 10000) *
                              box.maxWidth /
                              data.width,
                          color: Colors.grey.withValues(
                            alpha:
                                (double.tryParse(
                                          _fields['opacity']?.text ?? '.25',
                                        ) ??
                                        .25)
                                    .clamp(0, 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
    return image;
  }

  Widget _options() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 22, top: 12),
        child: Text('Options', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      ExtendedPdfOptions(
        tool: _id,
        options: {..._optionsMap, 'format': _format},
        field: _field,
        choice: _choice,
        onToggle: (name, value) => setState(() => _values[name] = value),
        onPick: _pickSecondary,
        locked: _filesLocked,
      ),
      if ([
            ToolId.convert,
            ToolId.editImage,
            ToolId.pdfOffice,
            ToolId.pdfImages,
          ].contains(_id) &&
          !(_id == ToolId.pdfImages && _values['imageMode'] == 'extract'))
        if (_targets.isNotEmpty)
          _choice('format', 'Output format', {
            for (final target in _targets) target: target.toUpperCase(),
          }, _format)
        else
          const Text(
            'These files have no common output format. Try a smaller selection.',
          ),
      if (_id == ToolId.convert)
        if (_canCombineImagesToPdf) ...[
          _choice('pdfOutput', 'PDF output', {
            'combined': 'One combined PDF',
            'separate': 'Separate PDFs',
          }, 'combined'),
          Text(
            _combineImages
                ? 'Images become PDF pages in the file list order.'
                : 'Each image is saved as its own PDF.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ] else
          const Text(
            'PDF → image exports all pages. Some Office formats and WebP output require an optional local helper.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
      if (_id == ToolId.pdfImages && _values['imageMode'] != 'extract')
        _field('dpi', 'Resolution (DPI)', initial: '150'),
      if (_id == ToolId.scanPdf) ...[
        _choice('scanMode', 'Scan appearance', {
          'color': 'Color',
          'grayscale': 'Grayscale',
          'blackAndWhite': 'Black and white',
        }, 'grayscale'),
        _scanSlider('contrast', 'Contrast', initial: 1.2, min: .5, max: 3),
        _scanSlider('brightness', 'Brightness', initial: 0, min: -.5, max: .5),
        if (_values['scanMode'] == 'blackAndWhite')
          _scanSlider(
            'threshold',
            'Black and white cutoff',
            initial: .6,
            min: .1,
            max: .9,
          ),
        _choice('dpi', 'Scan resolution', {
          '150': '150 DPI · smaller file',
          '200': '200 DPI · balanced',
          '300': '300 DPI · print quality',
        }, '150'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show original', style: TextStyle(fontSize: 14)),
          value: _showScanOriginal,
          onChanged: _busy
              ? null
              : (value) => setState(() => _showScanOriginal = value),
        ),
        const SizedBox(height: 12),
        const Text(
          'Settings apply to every page. Files are combined in the order shown. The new PDF contains page images; text selection and search are not retained.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        const Text(
          'PDFs, images and supported documents can be scanned. Document layouts follow the PDF converter; some Office formats need a local helper.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
      if (_id == ToolId.extract || _id == ToolId.organize)
        _field(
          'pages',
          _id == ToolId.organize ? 'Page order' : 'Pages to extract',
          hint: _id == ToolId.organize ? '3, 1, 2' : '1-3, 5',
          help: _id == ToolId.organize
              ? 'Enter pages in the desired order. Omit a page to remove it, or repeat it to duplicate it.'
              : 'Page numbers start at 1. Ranges and commas are supported.',
        ),
      if (_id == ToolId.rotate || _id == ToolId.editImage)
        _choice('degrees', 'Rotation', {
          if (_id == ToolId.editImage) '0': 'No rotation',
          '90': '90° clockwise',
          '180': '180°',
          '270': '270° clockwise',
        }, _id == ToolId.editImage ? '0' : '90'),
      if (_id == ToolId.crop) ...[
        const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: Text(
            'Drag the crop area in the preview, or enter margins in points (72 pt = 1 inch).',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ),
        Row(
          children: [
            Expanded(child: _field('left', 'Left', initial: '0')),
            const SizedBox(width: 12),
            Expanded(child: _field('right', 'Right', initial: '0')),
          ],
        ),
        Row(
          children: [
            Expanded(child: _field('top', 'Top', initial: '0')),
            const SizedBox(width: 12),
            Expanded(child: _field('bottom', 'Bottom', initial: '0')),
          ],
        ),
      ],
      if (_id == ToolId.compress)
        _choice('level', 'Compression', const {
          'ebook': 'Balanced · ebook',
          'screen': 'Smallest · screen',
          'print': 'High quality · print',
          'lossless': 'Lossless',
        }, 'ebook'),
      if (_id == ToolId.protect ||
          _id == ToolId.unlock ||
          _id == ToolId.info) ...[
        _field(
          'password',
          _id == ToolId.protect
              ? 'New password'
              : 'PDF password${_id == ToolId.info ? ' (if encrypted)' : ''}',
          secret: true,
        ),
        if (_id == ToolId.protect)
          _field('confirmPassword', 'Confirm password', secret: true),
        const Text(
          'Passwords are used for this run only and never saved.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
      if (_id == ToolId.redact) ...[
        _field(
          'text',
          'Text to permanently redact',
          help:
              'All matching text spans will be removed. Scanned pages need OCR, which is not included.',
        ),
        const Text(
          'Inspect every page of the result before sharing sensitive files.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
      if (_id == ToolId.pdfa) ...[
        _choice('pdfaLevel', 'PDF/A level', const {
          '1': 'PDF/A-1',
          '2': 'PDF/A-2',
          '3': 'PDF/A-3',
        }, '2'),
        const Text(
          'Exports use the bundled engine. Independent conformance validation is not included.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
      if (_id == ToolId.editImage) ...[
        Wrap(
          spacing: 20,
          children: [
            _flip('flipHorizontal', 'Flip horizontal'),
            _flip('flipVertical', 'Flip vertical'),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _field('width', 'Width (px)', hint: 'Auto')),
            const SizedBox(width: 12),
            Expanded(child: _field('height', 'Height (px)', hint: 'Auto')),
          ],
        ),
        _field('quality', 'JPEG / WebP quality (1–100)', initial: '85'),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() => _advancedCrop = !_advancedCrop),
          icon: Icon(
            _advancedCrop ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          label: Text(_advancedCrop ? 'Done selecting crop' : 'Crop rectangle'),
        ),
        if (_advancedCrop) ...[
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    _resetting = true;
                    for (final name in [
                      'cropX',
                      'cropY',
                      'cropWidth',
                      'cropHeight',
                    ]) {
                      _fields[name]?.clear();
                    }
                    _resetting = false;
                    setState(() {});
                  },
            child: const Text('Clear crop'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Crop after rotation/flip, before resize. Fill all four values or leave blank.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Row(
            children: [
              Expanded(child: _field('cropX', 'X (px)')),
              const SizedBox(width: 12),
              Expanded(child: _field('cropY', 'Y (px)')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _field('cropWidth', 'Crop width')),
              const SizedBox(width: 12),
              Expanded(child: _field('cropHeight', 'Crop height')),
            ],
          ),
        ],
      ],
      if ([ToolId.merge, ToolId.pageNumbers, ToolId.pdfText].contains(_id))
        const Text(
          'Ready when you are. Choose files and run the tool to save a new result.',
          style: TextStyle(color: AppTheme.muted),
        ),
    ],
  );
  Widget _scanSlider(
    String name,
    String label, {
    required double initial,
    required double min,
    required double max,
  }) {
    final value = (_values[name] as num?)?.toDouble() ?? initial;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14)),
              ),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
          Slider(
            key: ValueKey('scan-$name'),
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 100).round(),
            label: '${(value * 100).round()}%',
            semanticFormatterCallback: (v) =>
                '$label ${(v * 100).round()} percent',
            onChanged: _busy ? null : (v) => setState(() => _values[name] = v),
          ),
        ],
      ),
    );
  }

  Widget _flip(String key, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(
        value: _values[key] == true,
        onChanged: _busy
            ? null
            : (value) => setState(() => _values[key] = value!),
      ),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
