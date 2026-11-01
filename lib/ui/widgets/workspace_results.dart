import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/tool_definition.dart';
import '../../services/gui/gui_executor.dart';
import '../../services/gui/local_preview_service.dart';
import '../tool_icons.dart';
import 'file_preview_view.dart';

class WorkspaceResults extends StatelessWidget {
  final GuiResult result;
  final ToolId tool;
  final LocalPreviewService previews;
  final Future<void> Function(String, {bool reveal}) onOpen;
  final void Function(ToolDefinition, List<String>)? onContinue;
  const WorkspaceResults({
    super.key,
    required this.result,
    required this.tool,
    required this.previews,
    required this.onOpen,
    this.onContinue,
  });
  @override
  Widget build(BuildContext context) {
    final nextTools = ToolDefinition.tools
        .where(
          (next) =>
              result.outputs.isNotEmpty &&
              result.outputs.every(
                (path) => next.accepts(FileUtils.getExtension(path)),
              ) &&
              (next.id != ToolId.merge || result.outputs.length > 1),
        )
        .toList();
    final metrics = result.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: AppTheme.teal,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.outputs.isEmpty
                    ? 'Inspection complete'
                    : '${result.outputs.length} ${result.outputs.length == 1 ? 'file' : 'files'} ready',
                style: const TextStyle(
                  color: AppTheme.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (nextTools.isNotEmpty && onContinue != null)
              PopupMenuButton<ToolDefinition>(
                tooltip: 'Use results in another tool',
                onSelected: (next) => onContinue!(next, result.outputs),
                itemBuilder: (context) => nextTools
                    .map(
                      (next) => PopupMenuItem(
                        value: next,
                        child: Row(
                          children: [
                            Icon(toolIcon(next.id), size: 18),
                            const SizedBox(width: 10),
                            Text(next.title),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        'Use result in…',
                        style: TextStyle(color: AppTheme.amber),
                      ),
                      SizedBox(width: 5),
                      Icon(Icons.arrow_drop_down, color: AppTheme.amber),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (tool == ToolId.compress && metrics.inputBytes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${FileUtils.formatBytes(metrics.inputBytes)} → ${FileUtils.formatBytes(metrics.outputBytes)} · '
              '${metrics.outputBytes < metrics.inputBytes ? '${((1 - metrics.outputBytes / metrics.inputBytes) * 100).toStringAsFixed(1)}% smaller' : 'Already optimized; original size retained'}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
        if (metrics.elapsedMs > 0)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'Completed locally in ${(metrics.elapsedMs / 1000).toStringAsFixed(metrics.elapsedMs < 1000 ? 2 : 1)}s',
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
        if (result.details.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: result.details.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(result.details[index]),
              ),
            ),
          ),
        if (result.outputs.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 330),
            child: ListView.builder(
              shrinkWrap: true,
              itemExtent: 84,
              itemCount: result.outputs.length,
              itemBuilder: (context, index) {
                final output = result.outputs[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: InkWell(
                    onTap: () => showLocalPreview(
                      context,
                      output,
                      previews,
                      openOriginal: (path) => onOpen(path),
                    ),
                    child: SizedBox(
                      width: 44,
                      height: 62,
                      child: FilePreviewView(
                        path: output,
                        service: previews,
                        thumbnail: true,
                      ),
                    ),
                  ),
                  title: Text(
                    p.basename(output),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_size(output)),
                  onTap: () => showLocalPreview(
                    context,
                    output,
                    previews,
                    openOriginal: (path) => onOpen(path),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Preview result',
                        onPressed: () => showLocalPreview(
                          context,
                          output,
                          previews,
                          openOriginal: (path) => onOpen(path),
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 19),
                      ),
                      IconButton(
                        tooltip: 'Open result',
                        onPressed: () => onOpen(output),
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                      IconButton(
                        tooltip: Platform.isWindows
                            ? 'Show in Explorer'
                            : Platform.isMacOS
                            ? 'Show in Finder'
                            : 'Show in file manager',
                        onPressed: () => onOpen(output, reveal: true),
                        icon: const Icon(Icons.folder_open_outlined, size: 19),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _size(String path) {
    try {
      final stat = File(path).statSync();
      return stat.type == FileSystemEntityType.file
          ? FileUtils.formatBytes(stat.size)
          : 'File moved or deleted';
    } catch (_) {
      return 'File unavailable';
    }
  }
}
