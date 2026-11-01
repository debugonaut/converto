import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/gui/local_preview_service.dart';
import '../../services/pdf/pdf_engine.dart';
import 'file_preview_view.dart';

class _PageItem {
  final int id;
  final int source;
  final int rotation;
  const _PageItem(this.id, this.source, [this.rotation = 0]);
}

class PdfPageControls extends StatefulWidget {
  final String path;
  final int pageCount;
  final LocalPreviewService service;
  final TextEditingController expression;
  final bool organize;
  final bool selectable;
  final bool enabled;
  final ValueChanged<List<int>>? onRotations;
  final ValueChanged<int>? onInspectPage;
  const PdfPageControls({
    super.key,
    required this.path,
    required this.pageCount,
    required this.service,
    required this.expression,
    this.organize = false,
    this.selectable = false,
    this.enabled = true,
    this.onRotations,
    this.onInspectPage,
  });
  @override
  State<PdfPageControls> createState() => _PdfPageControlsState();
}

class _PdfPageControlsState extends State<PdfPageControls> {
  List<_PageItem> _pages = [];
  Set<int> _selected = {};
  bool _emitting = false;
  int _nextId = 0;
  @override
  void initState() {
    super.initState();
    _sync();
    widget.expression.addListener(_expressionChanged);
  }

  @override
  void didUpdateWidget(covariant PdfPageControls old) {
    super.didUpdateWidget(old);
    if (old.expression != widget.expression) {
      old.expression.removeListener(_expressionChanged);
      widget.expression.addListener(_expressionChanged);
      _sync();
    }
    if (old.pageCount != widget.pageCount || old.path != widget.path) _sync();
  }

  @override
  void dispose() {
    widget.expression.removeListener(_expressionChanged);
    super.dispose();
  }

  void _sync() {
    var indices = List.generate(widget.pageCount, (i) => i);
    if (widget.expression.text.trim().isNotEmpty) {
      try {
        indices = PdfEngine.parsePageList(
          widget.expression.text,
          widget.pageCount,
        );
      } catch (_) {
        return;
      }
    } else if (widget.selectable) {
      indices = [];
    }
    if (widget.organize) {
      _pages = indices.map((page) => _PageItem(_nextId++, page)).toList();
    } else {
      _selected = indices.toSet();
      _pages = List.generate(
        widget.pageCount,
        (page) => _PageItem(_nextId++, page),
      );
    }
  }

  void _expressionChanged() {
    if (!_emitting && mounted) setState(_sync);
  }

  void _emit() {
    _emitting = true;
    final indices = widget.organize
        ? _pages.map((page) => page.source).toList()
        : (_selected.toList()..sort());
    widget.expression.text = indices.map((page) => '${page + 1}').join(',');
    _emitting = false;
    if (widget.organize)
      widget.onRotations?.call(_pages.map((page) => page.rotation).toList());
  }

  void _move(int from, int to) {
    setState(() {
      final page = _pages.removeAt(from);
      _pages.insert(to, page);
      _emit();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Text(
              widget.organize
                  ? 'Arrange pages'
                  : widget.selectable
                  ? 'Select pages'
                  : 'Pages',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.selectable)
            TextButton(
              onPressed: widget.enabled
                  ? () => setState(() {
                      _selected = List.generate(
                        widget.pageCount,
                        (i) => i,
                      ).toSet();
                      _emit();
                    })
                  : null,
              child: const Text('All'),
            ),
          if (widget.selectable)
            TextButton(
              onPressed: widget.enabled
                  ? () => setState(() {
                      _selected.clear();
                      _emit();
                    })
                  : null,
              child: const Text('None'),
            ),
          if (widget.organize)
            TextButton(
              onPressed: widget.enabled
                  ? () => setState(() {
                      widget.expression.clear();
                      _sync();
                      _emit();
                    })
                  : null,
              child: const Text('Reset pages'),
            ),
        ],
      ),
      if (widget.organize)
        const Text(
          'Drag pages to reorder. Rotate, duplicate or remove individual pages.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      const SizedBox(height: 10),
      SizedBox(
        height: widget.organize ? 220 : 175,
        child: _pages.isEmpty
            ? const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'All pages removed. Reset pages to start again.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              )
            : widget.organize
            ? ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                itemExtent: 132,
                buildDefaultDragHandles: false,
                itemCount: _pages.length,
                // Supports the project's Flutter 3.38 minimum as well as current Flutter.
                // ignore: deprecated_member_use
                onReorder: (old, next) {
                  if (widget.enabled) _move(old, next > old ? next - 1 : next);
                },
                itemBuilder: (context, index) => _card(index, reorder: true),
              )
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                itemExtent: 128,
                itemCount: _pages.length,
                itemBuilder: (context, index) => _card(index),
              ),
      ),
    ],
  );
  Widget _card(int index, {bool reorder = false}) {
    final page = _pages[index];
    final selected = !widget.selectable || _selected.contains(page.source);
    return Padding(
      key: ValueKey(page.id),
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: selected
                      ? AppTheme.amber.withValues(alpha: .65)
                      : AppTheme.border,
                ),
              ),
              child: InkWell(
                onTap: !widget.enabled
                    ? null
                    : () {
                        if (widget.selectable) {
                          setState(() {
                            if (!_selected.add(page.source))
                              _selected.remove(page.source);
                            _emit();
                          });
                        } else {
                          widget.onInspectPage?.call(page.source);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: RotatedBox(
                    quarterTurns: page.rotation ~/ 90,
                    child: FilePreviewView(
                      path: widget.path,
                      service: widget.service,
                      thumbnail: true,
                      initialPage: page.source,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.selectable)
                  SizedBox(
                    width: 24,
                    child: Checkbox(
                      value: selected,
                      onChanged: widget.enabled
                          ? (_) => setState(() {
                              if (!_selected.add(page.source))
                                _selected.remove(page.source);
                              _emit();
                            })
                          : null,
                    ),
                  ),
                Text(
                  'Page ${page.source + 1}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
                if (reorder)
                  ReorderableDragStartListener(
                    enabled: widget.enabled,
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.organize)
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _icon(
                    'Rotate page ${page.source + 1}',
                    Icons.rotate_right,
                    () => setState(() {
                      _pages[index] = _PageItem(
                        page.id,
                        page.source,
                        (page.rotation + 90) % 360,
                      );
                      _emit();
                    }),
                  ),
                  _icon(
                    'Duplicate page ${page.source + 1}',
                    Icons.copy_outlined,
                    () => setState(() {
                      _pages.insert(
                        index + 1,
                        _PageItem(_nextId++, page.source, page.rotation),
                      );
                      _emit();
                    }),
                  ),
                  _icon(
                    'Remove page ${page.source + 1}',
                    Icons.close,
                    () => setState(() {
                      _pages.removeAt(index);
                      _emit();
                    }),
                  ),
                ],
              ),
            ),
          if (widget.organize)
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _icon(
                    'Move page left',
                    Icons.chevron_left,
                    index == 0 ? null : () => _move(index, index - 1),
                  ),
                  _icon(
                    'Move page right',
                    Icons.chevron_right,
                    index + 1 == _pages.length
                        ? null
                        : () => _move(index, index + 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon(String label, IconData icon, VoidCallback? callback) =>
      IconButton(
        tooltip: label,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        iconSize: 16,
        onPressed: widget.enabled ? callback : null,
        icon: Icon(icon),
      );
}
