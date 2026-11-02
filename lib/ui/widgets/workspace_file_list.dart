import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/file_preview.dart';
import '../../models/gui/tool_definition.dart';
import '../../services/gui/local_preview_service.dart';
import '../../services/gui/mobile_documents.dart';
import '../../services/gui/output_names.dart';
import 'file_preview_view.dart';
import 'output_name_field.dart';

class WorkspaceFileList extends StatelessWidget {
  final ToolDefinition tool;
  final List<String> paths;
  final LocalPreviewService service;
  final bool locked;
  final bool combinedOutput;
  final int reloadToken;
  final String? activePath;
  final String? failedPath;
  final String extension;
  final Map<String, FilePreview> metadata;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<String> onPreview;
  final ValueChanged<FilePreview> onMetadata;
  final TextEditingController Function(String) nameController;
  const WorkspaceFileList({
    super.key,
    required this.tool,
    required this.paths,
    required this.service,
    required this.locked,
    this.combinedOutput = false,
    this.reloadToken = 0,
    required this.extension,
    required this.onChanged,
    required this.onPreview,
    required this.onMetadata,
    required this.nameController,
    this.activePath,
    this.failedPath,
    this.metadata = const {},
  });
  bool get _perFileNames =>
      paths.length > 1 &&
      !combinedOutput &&
      tool.id != ToolId.merge &&
      tool.id != ToolId.info;
  void _move(int from, int to) {
    final next = List.of(paths);
    final item = next.removeAt(from);
    next.insert(to, item);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: _perFileNames ? 360 : 240),
    child: ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      itemExtent:
          (_perFileNames ? 148.0 : 92.0) +
          (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(0, 5) *
              (_perFileNames ? 110 : 50) +
          (_perFileNames &&
                  paths.any(
                    (path) =>
                        OutputNames.fieldError(
                          nameController(path).text,
                          extension,
                        ) !=
                        null,
                  )
              ? 34
              : 0),
      itemCount: paths.length,
      // Retains support for the declared Flutter 3.38 minimum.
      // ignore: deprecated_member_use
      onReorder: (old, next) {
        if (!locked) _move(old, next > old ? next - 1 : next);
      },
      itemBuilder: (context, index) {
        final path = paths[index];
        final accepted = tool.accepts(FileUtils.getExtension(path));
        return Container(
          key: ValueKey(path),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: failedPath == path
                  ? Theme.of(context).colorScheme.error
                  : activePath == path
                  ? AppTheme.amber.withValues(alpha: .65)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (!MobileDocuments.enabled)
                      ReorderableDragStartListener(
                        index: index,
                        enabled: !locked,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () => onPreview(path),
                      child: SizedBox(
                        width: 48,
                        height: 64,
                        child: FilePreviewView(
                          path: path,
                          service: service,
                          thumbnail: true,
                          reloadToken: reloadToken,
                          onMetadata: onMetadata,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Tooltip(
                            message: path,
                            child: Text(
                              p.basename(path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: accepted
                                    ? null
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !accepted
                                ? 'Incompatible with this tool'
                                : '${FileUtils.getExtension(path).toUpperCase()}${metadata[path] == null ? '' : ' · ${FileUtils.formatBytes(metadata[path]!.sizeBytes)}${metadata[path]!.kind == 'pdf' ? ' · ${metadata[path]!.pageCount} pages' : ''}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: accepted
                                  ? AppTheme.muted
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (paths.length > 1 && !MobileDocuments.enabled)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _moveButton(
                            'Move up',
                            Icons.keyboard_arrow_up,
                            locked || index == 0
                                ? null
                                : () => _move(index, index - 1),
                          ),
                          _moveButton(
                            'Move down',
                            Icons.keyboard_arrow_down,
                            locked || index + 1 == paths.length
                                ? null
                                : () => _move(index, index + 1),
                          ),
                        ],
                      ),
                    if (MobileDocuments.enabled)
                      PopupMenuButton<String>(
                        tooltip: 'File actions',
                        enabled: !locked,
                        onSelected: (action) {
                          if (action == 'up') {
                            _move(index, index - 1);
                          } else if (action == 'down') {
                            _move(index, index + 1);
                          } else {
                            final next = List.of(paths)..removeAt(index);
                            onChanged(next);
                          }
                        },
                        itemBuilder: (_) => [
                          if (index > 0)
                            const PopupMenuItem(
                              value: 'up',
                              child: Text('Move up'),
                            ),
                          if (index + 1 < paths.length)
                            const PopupMenuItem(
                              value: 'down',
                              child: Text('Move down'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove file'),
                          ),
                        ],
                      )
                    else
                      IconButton(
                        tooltip: 'Remove file',
                        onPressed: locked
                            ? null
                            : () {
                                final next = List.of(paths)..removeAt(index);
                                onChanged(next);
                              },
                        icon: const Icon(Icons.close, size: 17),
                      ),
                  ],
                ),
              ),
              if (_perFileNames)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: OutputNameField(
                    controller: nameController(path),
                    extension: extension,
                    enabled: !locked,
                    compact: true,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  Widget _moveButton(String label, IconData icon, VoidCallback? action) =>
      IconButton(
        tooltip: label,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 17),
        onPressed: action,
      );
}
