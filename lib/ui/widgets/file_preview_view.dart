import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/file_preview.dart';
import '../../services/gui/local_preview_service.dart';

class FilePreviewView extends StatefulWidget {
  final String path;
  final LocalPreviewService service;
  final bool thumbnail;
  final int initialPage;
  final String? password;
  final int reloadToken;
  final ValueChanged<FilePreview>? onMetadata;
  final Widget Function(FilePreview, Widget)? imageBuilder;
  final ValueChanged<int>? onPageChanged;
  const FilePreviewView({
    super.key,
    required this.path,
    required this.service,
    this.thumbnail = false,
    this.initialPage = 0,
    this.password,
    this.reloadToken = 0,
    this.onMetadata,
    this.imageBuilder,
    this.onPageChanged,
  });
  @override
  State<FilePreviewView> createState() => _FilePreviewViewState();
}

class _FilePreviewViewState extends State<FilePreviewView> {
  late Future<FilePreview> _future;
  late int _page;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _load();
  }

  @override
  void didUpdateWidget(covariant FilePreviewView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.initialPage != widget.initialPage ||
        old.password != widget.password ||
        old.reloadToken != widget.reloadToken) {
      _page = widget.initialPage;
      _load();
    }
  }

  void _load() {
    final generation = ++_loadGeneration;
    final path = widget.path, page = _page;
    _future = widget.service.load(
      path,
      page: page,
      dimension: widget.thumbnail ? 160 : 1200,
      password: widget.password,
    );
    _future.then((value) {
      if (mounted &&
          generation == _loadGeneration &&
          path == widget.path &&
          page == _page)
        widget.onMetadata?.call(value);
    });
  }

  void _go(int page) {
    setState(() {
      _page = page;
      _load();
    });
    widget.onPageChanged?.call(page);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FilePreview>(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: widget.thumbnail
                ? const Icon(Icons.description_outlined, color: AppTheme.muted)
                : const Text(
                    'Preparing local preview…',
                    style: TextStyle(color: AppTheme.muted),
                  ),
          ),
        );
      }
      Widget content;
      if (data.image != null) {
        content = Image.memory(
          data.image!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: '${p.basename(widget.path)}, page ${_page + 1}',
          errorBuilder: (_, __, ___) =>
              const Center(child: Text('Cannot display this preview.')),
        );
        if (widget.imageBuilder != null)
          content = widget.imageBuilder!(data, content);
      } else if (data.text?.isNotEmpty ?? false) {
        content = widget.thumbnail
            ? const Icon(Icons.notes, size: 30, color: AppTheme.muted)
            : Container(
                color: const Color(0xFFF4F2EC),
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: SelectableText(
                    data.text!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Color(0xFF292A29),
                    ),
                  ),
                ),
              );
      } else {
        content = Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: widget.thumbnail
                ? Icon(
                    data.encrypted
                        ? Icons.lock_outline
                        : data.kind == 'error'
                        ? Icons.warning_amber_outlined
                        : Icons.insert_drive_file_outlined,
                    color: AppTheme.muted,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        data.encrypted
                            ? Icons.lock_outline
                            : Icons.description_outlined,
                        size: 36,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        data.message ?? 'Open original to view this file.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          widget.service.clear();
                          _load();
                        }),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry preview'),
                      ),
                    ],
                  ),
          ),
        );
      }
      if (widget.thumbnail)
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: content,
        );
      return Column(
        children: [
          Expanded(
            child: ClipRect(child: SizedBox.expand(child: content)),
          ),
          const SizedBox(height: 10),
          if (data.kind == 'pdf' || data.kind == 'image' || data.pageCount > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => _go(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${data.kind == 'image'
                      ? 'Frame'
                      : data.kind == 'text' && data.pageCount > 1
                      ? 'Slide'
                      : 'Page'} ${_page + 1} of ${data.pageCount}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _page + 1 < data.pageCount
                      ? () => _go(_page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          if (['text', 'document'].contains(data.kind) && data.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                data.message!,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      );
    },
  );
}

Future<void> showLocalPreview(
  BuildContext context,
  String path,
  LocalPreviewService service, {
  Future<void> Function(String)? openOriginal,
  int initialPage = 0,
  Widget Function(FilePreview, Widget)? imageBuilder,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _PreviewDialog(
      path: path,
      service: service,
      initialPage: initialPage,
      openOriginal: openOriginal,
      imageBuilder: imageBuilder,
    ),
  );
}

class _PreviewDialog extends StatefulWidget {
  final String path;
  final LocalPreviewService service;
  final Future<void> Function(String)? openOriginal;
  final int initialPage;
  final Widget Function(FilePreview, Widget)? imageBuilder;
  const _PreviewDialog({
    required this.path,
    required this.service,
    required this.initialPage,
    this.openOriginal,
    this.imageBuilder,
  });
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  final _password = TextEditingController();
  String? _previewPassword;
  FilePreview? _metadata;
  bool _fitted = true;
  final _transform = TransformationController();
  @override
  void dispose() {
    _password.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double scale) {
    setState(() {
      _fitted = false;
      _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(28),
    child: SizedBox(
      width: 1000,
      height: MediaQuery.sizeOf(context).height * .87,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(widget.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_metadata != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${FileUtils.formatBytes(_metadata!.sizeBytes)}${_metadata!.width > 0 ? ' · ${_metadata!.width.round()} × ${_metadata!.height.round()} ${_metadata!.kind == 'pdf' ? 'pt' : 'px'}' : ''}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            if (_metadata?.encrypted == true && _metadata?.kind == 'error')
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'PDF password',
                      ),
                      onSubmitted: (value) => setState(() {
                        _previewPassword = value;
                        _password.clear();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _previewPassword = _password.text;
                      _password.clear();
                    }),
                    child: const Text('Unlock preview'),
                  ),
                ],
              ),
            Expanded(
              child: FilePreviewView(
                path: widget.path,
                service: widget.service,
                initialPage: widget.initialPage,
                password: _previewPassword,
                onMetadata: (data) {
                  if (_metadata?.kind != data.kind ||
                      _metadata?.width != data.width ||
                      _metadata?.encrypted != data.encrypted ||
                      _metadata?.sizeBytes != data.sizeBytes)
                    setState(() => _metadata = data);
                },
                imageBuilder: (data, image) => InteractiveViewer(
                  transformationController: _transform,
                  minScale: .5,
                  maxScale: 4,
                  child: Center(
                    child: widget.imageBuilder?.call(data, image) ?? image,
                  ),
                ),
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _transform.value = Matrix4.identity();
                    _fitted = true;
                  }),
                  child: Text(_fitted ? 'Fit to window' : 'Fit'),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(
                    math.max(.5, _transform.value.getMaxScaleOnAxis() / 1.25),
                  ),
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: () => _zoom(
                    math.min(4, _transform.value.getMaxScaleOnAxis() * 1.25),
                  ),
                  icon: const Icon(Icons.zoom_in),
                ),
                if (widget.openOriginal != null)
                  TextButton.icon(
                    onPressed: () => widget.openOriginal!(widget.path),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open original'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
