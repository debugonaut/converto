import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
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
  ToolId get _id => widget.tool.id;
  bool get _busy => widget.job.busy;
  List<String> get _targets =>
      widget.tool.targets(widget.paths.map(FileUtils.getExtension));
  String get _format =>
      _values['format'] as String? ?? (_targets.firstOrNull ?? 'pdf');
  @override
  void didUpdateWidget(covariant ToolWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_targets.contains(_format)) _values.remove('format');
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String name, String initial) =>
      _fields.putIfAbsent(name, () => TextEditingController(text: initial));
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
      onChanged: (value) => _values[name] = value,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
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
    if (widget.outputDirectory == null) return;
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
      ),
      remember: widget.remember,
    );
    for (final key in ['password', 'confirmPassword']) {
      _fields[key]?.clear();
      _values.remove(key);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final incompatible = widget.paths
        .where((path) => !widget.tool.accepts(FileUtils.getExtension(path)))
        .length;
    final valid =
        widget.paths.isNotEmpty &&
        incompatible == 0 &&
        _targets.isNotEmpty &&
        (_id != ToolId.merge || widget.paths.length >= 2) &&
        widget.outputDirectory != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(44, 24, 44, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 17),
                label: const Text('All tools'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(toolIcon(_id), size: 30, color: AppTheme.amber),
                  const SizedBox(width: 14),
                  Text(
                    widget.tool.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                widget.tool.description,
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 30),
              LayoutBuilder(
                builder: (context, constraints) {
                  final files = _files(incompatible);
                  final options = _options();
                  if (constraints.maxWidth < 820)
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [files, const SizedBox(height: 30), options],
                    );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: files),
                      const SizedBox(width: 40),
                      Expanded(flex: 5, child: options),
                    ],
                  );
                },
              ),
              const SizedBox(height: 26),
              const Divider(),
              const SizedBox(height: 24),
              if (_id != ToolId.info) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.outputDirectory ?? 'Loading output folder…',
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : widget.onChooseOutput,
                      child: const Text('Change folder'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  FilledButton.icon(
                    key: const Key('run-tool'),
                    onPressed: valid && !_busy ? _run : null,
                    icon: Icon(
                      _id == ToolId.info
                          ? Icons.info_outline
                          : Icons.play_arrow_rounded,
                      size: 19,
                    ),
                    label: Text(
                      _busy
                          ? 'Processing…'
                          : _id == ToolId.info
                          ? 'Inspect files'
                          : 'Run ${widget.tool.title.toLowerCase()}',
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_busy)
                    TextButton(
                      onPressed: widget.job.cancelling
                          ? null
                          : widget.job.cancel,
                      child: const Text('Cancel'),
                    ),
                  if (!_busy)
                    const Flexible(
                      child: Text(
                        'Original files are kept.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 22),
                LinearProgressIndicator(
                  value: widget.job.progress > 0 ? widget.job.progress : null,
                  backgroundColor: AppTheme.border,
                  color: AppTheme.amber,
                  minHeight: 3,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.job.message,
                  style: const TextStyle(color: AppTheme.muted),
                ),
              ],
              if (!_busy && widget.job.message.startsWith('Cancelled')) ...[
                const SizedBox(height: 20),
                Text(
                  widget.job.message,
                  style: const TextStyle(color: AppTheme.muted),
                ),
              ],
              if (widget.job.error != null) ...[
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        widget.job.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.job.result != null && !_busy) ...[
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.teal,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.job.result!.outputs.isEmpty
                          ? 'Inspection complete'
                          : '${widget.job.result!.outputs.length} files ready',
                      style: const TextStyle(
                        color: AppTheme.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                for (final detail in widget.job.result!.details)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SelectableText(detail),
                  ),
                for (final output in widget.job.result!.outputs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.basename(output)),
                    subtitle: Text(
                      FileUtils.formatBytes(File(output).lengthSync()),
                    ),
                    onTap: () => widget.onOpen(output),
                    trailing: IconButton(
                      tooltip: 'Show in Finder',
                      onPressed: () => widget.onOpen(output, reveal: true),
                      icon: const Icon(Icons.folder_open_outlined),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _files(int incompatible) => Column(
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
              onPressed: _busy ? null : () => widget.onPathsChanged([]),
              child: const Text('Clear'),
            ),
          TextButton.icon(
            onPressed: _busy ? null : widget.onPick,
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: _busy ? null : widget.onPick,
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
                  'Nothing runs until you say so.',
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ),
      if (widget.paths.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.paths.length,
            itemBuilder: (context, index) {
              final path = widget.paths[index];
              final accepted = widget.tool.accepts(
                FileUtils.getExtension(path),
              );
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  accepted
                      ? Icons.insert_drive_file_outlined
                      : Icons.error_outline,
                  color: accepted
                      ? AppTheme.muted
                      : Theme.of(context).colorScheme.error,
                  size: 22,
                ),
                title: Tooltip(
                  message: path,
                  child: Text(
                    p.basename(path),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle: Text(
                  accepted
                      ? FileUtils.getExtension(path).toUpperCase()
                      : 'Incompatible with this tool',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_id == ToolId.merge) ...[
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: _busy || index == 0
                            ? null
                            : () {
                                final paths = List.of(widget.paths);
                                final file = paths.removeAt(index);
                                paths.insert(index - 1, file);
                                widget.onPathsChanged(paths);
                              },
                        icon: const Icon(Icons.arrow_upward, size: 16),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: _busy || index == widget.paths.length - 1
                            ? null
                            : () {
                                final paths = List.of(widget.paths);
                                final file = paths.removeAt(index);
                                paths.insert(index + 1, file);
                                widget.onPathsChanged(paths);
                              },
                        icon: const Icon(Icons.arrow_downward, size: 16),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Remove file',
                      onPressed: _busy
                          ? null
                          : () {
                              final paths = List.of(widget.paths)
                                ..removeAt(index);
                              widget.onPathsChanged(paths);
                            },
                      icon: const Icon(Icons.close, size: 17),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      if (incompatible > 0)
        Text(
          'Remove $incompatible incompatible files to continue.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_id == ToolId.merge)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Use the arrows to arrange files. Choose at least two files.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
      if (_id == ToolId.editImage && widget.paths.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Text(
          'Original preview',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: Image.file(
            File(widget.paths.first),
            cacheWidth: 640,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text(
                'Preview unavailable for this format.\nThe local image engine can still process it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          ),
        ),
      ],
    ],
  );
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
      ],
      if (_id == ToolId.crop) ...[
        const Padding(
          padding: EdgeInsets.only(bottom: 18),
          child: Text(
            'Margins in PDF points (72 pt = 1 inch).',
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
          label: const Text('Crop rectangle'),
        ),
        if (_advancedCrop) ...[
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
