import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/edit_options.dart';
import '../../models/gui/file_preview.dart';
import '../../services/gui/local_preview_service.dart';
import '../../services/gui/output_names.dart';
import '../../services/gui/workspace_validation.dart';
import '../widgets/file_preview_view.dart';
import '../widgets/output_name_field.dart';
import '../widgets/workspace_file_list.dart';
import '../widgets/workspace_results.dart';
import '../widgets/pdf_page_controls.dart';
import '../widgets/crop_overlay.dart';
import '../widgets/image_edit_preview.dart';
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
  late final LocalPreviewService _previews;
  final _names = <String, TextEditingController>{};
  final _metadata = <String, FilePreview>{};
  final _touched = <String>{};
  final _mergeName = TextEditingController(text: 'merged');
  final _scroll = ScrollController();
  String? _activePath;
  bool _resetting = false;
  int _previewRevision = 0;
  int get _reloadToken => _previewRevision + widget.intakeRevision;

  @override
  void initState() {
    super.initState();
    _previews = widget.previews ?? LocalPreviewService();
    _activePath = widget.paths.firstOrNull;
    _mergeName.addListener(_formChanged);
    widget.job.addListener(_jobChanged);
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
      ToolId.split => 'part',
      _ => '',
    };
    return suffix.isEmpty ? base : '${base}_$suffix';
  }

  String get _extension => _id == ToolId.pdfText
      ? 'txt'
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
    'dpi': '150',
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
      (_id == ToolId.merge
          ? OutputNames.fieldError(_mergeName.text, _extension) == null
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
    _resetting = true;
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    _values.clear();
    _touched.clear();
    _advancedCrop = false;
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
  bool get _filesLocked => _busy || widget.addingFiles;
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
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final controller in _names.values) {
      controller.dispose();
    }
    _mergeName.dispose();
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
      enabled: !_busy,
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
      onChanged: _busy
          ? null
          : (value) => setState(() => _values[name] = value!),
    ),
  );
  Future<void> _run() async {
    if (widget.outputDirectory == null ||
        widget.addingFiles ||
        _errors.isNotEmpty ||
        !_namesValid)
      return;
    FocusScope.of(context).unfocus();
    final options = <String, Object>{..._values};
    for (final entry in _fields.entries) {
      options[entry.key] = entry.value.text;
    }
    options['format'] = _format;
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
            : _id == ToolId.merge
            ? _mergeName.text
            : widget.paths.length == 1
            ? _name(widget.paths.single).text
            : null,
        outputNames:
            _id == ToolId.merge || _id == ToolId.info || widget.paths.length < 2
            ? const {}
            : {for (final path in widget.paths) path: _name(path).text},
      ),
      remember: widget.remember,
    );
    for (final key in ['password', 'confirmPassword']) {
      _fields[key]?.clear();
      _values.remove(key);
    }
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
        !widget.addingFiles &&
        widget.paths.isNotEmpty &&
        incompatible == 0 &&
        _targets.isNotEmpty &&
        (_id != ToolId.merge || widget.paths.length >= 2) &&
        widget.outputDirectory != null &&
        errors.isEmpty &&
        _namesValid;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : widget.onBack,
                          icon: const Icon(Icons.arrow_back, size: 17),
                          label: const Text('All tools'),
                        ),
                        const Spacer(),
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
                    LayoutBuilder(
                      builder: (context, box) {
                        final files = _files(incompatible);
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
                                      _id != ToolId.merge)
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
    padding: const EdgeInsets.fromLTRB(28, 13, 28, 12),
    decoration: const BoxDecoration(
      color: AppTheme.background,
      border: Border(top: BorderSide(color: AppTheme.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_id != ToolId.info &&
            (_id == ToolId.merge || widget.paths.length == 1)) ...[
          OutputNameField(
            controller: _id == ToolId.merge
                ? _mergeName
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
      Widget folder() => Row(
        children: [
          const Icon(Icons.folder_outlined, size: 17, color: AppTheme.muted),
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
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onChooseOutput,
            child: const Text('Change folder'),
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

  Widget _files(int incompatible) {
    final active = _activePath;
    final meta = _metadata[active];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Files${widget.paths.isEmpty ? '' : ' · ${widget.paths.length}'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
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
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    color: AppTheme.muted,
                    size: 30,
                  ),
                  SizedBox(height: 14),
                  Text('Drop files here or choose files'),
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
        if (_id == ToolId.merge)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Drag the handles to arrange files. Arrow buttons also move files.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
        if (active != null && _id != ToolId.merge) _sourcePreview(active, meta),
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
      if ([
        ToolId.convert,
        ToolId.editImage,
        ToolId.pdfOffice,
        ToolId.pdfImages,
      ].contains(_id))
        if (_targets.isNotEmpty)
          _choice('format', 'Output format', {
            for (final target in _targets) target: target.toUpperCase(),
          }, _format)
        else
          const Text(
            'These files have no common output format. Try a smaller selection.',
          ),
      if (_id == ToolId.convert)
        const Text(
          'PDF → image exports all pages. Some Office formats and WebP output require an optional local helper.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      if (_id == ToolId.pdfImages)
        _field('dpi', 'Resolution (DPI)', initial: '150'),
      if (_id == ToolId.split) ...[
        _field('every', 'Pages per part', initial: '1'),
        _field(
          'pages',
          'Or split by ranges',
          hint: '1-3, 4-6, 7',
          help:
              'Each comma-separated group becomes a PDF. Ranges override pages per part.',
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
      if (_id == ToolId.watermark) ...[
        _field('text', 'Watermark text', hint: 'DRAFT'),
        _field('opacity', 'Opacity (0–1)', initial: '0.25'),
        _field('angle', 'Angle (degrees)', initial: '45'),
        _field('fontSize', 'Font size (pt)', initial: '54'),
      ],
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
