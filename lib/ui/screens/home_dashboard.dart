import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/format_types.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/conversion_job.dart';
import '../../models/file_item.dart';
import '../../services/conversion_coordinator.dart';
import '../../services/history_service.dart';
import '../../services/storage_service.dart';

class HomeDashboard extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const HomeDashboard({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  bool _isDragging = false;
  PlatformCapabilities? _capabilities;
  List<HistoryItem> _recentHistory = [];

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
    _loadHistory();
  }

  Future<void> _loadCapabilities() async {
    final caps = await PlatformDetector.detect();
    if (mounted) {
      setState(() => _capabilities = caps);
    }
  }

  Future<void> _loadHistory() async {
    await HistoryService().init();
    if (mounted) {
      setState(() {
        _recentHistory = HistoryService().getHistory().take(6).toList();
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: FormatRegistry.allSupportedExtensions,
    );

    if (result != null && result.files.isNotEmpty) {
      final validFiles = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      _handleSelectedFiles(validFiles);
    }
  }

  void _handleSelectedFiles(List<File> files) {
    if (files.isEmpty) return;

    for (final file in files) {
      final fileItem = FileItem.fromFile(file);
      final availableTargets = FormatRegistry.getAvailableTargetFormats(fileItem.extension);
      final defaultTarget = availableTargets.first;

      final job = ConversionJob(
        id: const Uuid().v4(),
        sourceFile: fileItem,
        targetFormat: defaultTarget,
        createdAt: DateTime.now(),
      );

      ConversionCoordinator().addJob(job);
    }

    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWindows = _capabilities?.isWindows ?? false;
    final isAndroid = _capabilities?.isAndroid ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Converto',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '100% Offline',
                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'Open Output Folder',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () async {
              final dir = await StorageService().getOutputDirectory();
              await StorageService().showInFileManager(dir.path);
            },
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (detail) {
          setState(() => _isDragging = false);
          final files = detail.files.map((f) => File(f.path)).toList();
          _handleSelectedFiles(files);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device status indicator
              _buildDeviceBanner(isWindows, isAndroid),
              const SizedBox(height: 20),

              // Drop Zone / File Picker
              _buildDropZone(theme),
              const SizedBox(height: 24),

              // Active Conversion Queue
              _buildQueueSection(),
              const SizedBox(height: 28),

              // Quick Actions by Category
              Text('Convert by Format Category', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildCategoryGrid(),
              const SizedBox(height: 28),

              // Recent Conversion History
              Text('Recent Conversions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildRecentHistoryList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceBanner(bool isWindows, bool isAndroid) {
    String osLabel = 'Desktop / Mobile';
    if (isWindows) osLabel = 'Windows 64-bit';
    if (isAndroid) osLabel = 'Android Device';

    final hasLibreOffice = _capabilities?.hasLibreOfficeCLI ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Icon(
            isAndroid ? Icons.android : (isWindows ? Icons.desktop_windows : Icons.computer),
            size: 18,
            color: AppTheme.primaryCyan,
          ),
          const SizedBox(width: 8),
          Text(
            'Target Platform: $osLabel',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            hasLibreOffice ? 'LibreOffice Engine: Active' : 'Pure-Dart Engine: Active',
            style: TextStyle(
              fontSize: 11,
              color: hasLibreOffice ? Colors.green : Colors.blueGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropZone(ThemeData theme) {
    return GestureDetector(
      onTap: _pickFiles,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: _isDragging
              ? AppTheme.primaryBlue.withValues(alpha: 0.08)
              : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDragging ? AppTheme.primaryCyan : AppTheme.darkBorder,
            width: _isDragging ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.upload_file_rounded, size: 28, color: AppTheme.primaryCyan),
            ),
            const SizedBox(height: 14),
            const Text(
              'Drop files here or click to browse',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Supports PDF, Word (DOCX), Excel (XLSX), PowerPoint (PPTX), JPG, PNG, WEBP, CSV',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueSection() {
    return StreamBuilder<List<ConversionJob>>(
      stream: ConversionCoordinator().queueStream,
      initialData: ConversionCoordinator().currentQueue,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? [];
        if (queue.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Active Queue (${queue.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                TextButton(
                  onPressed: () {
                    ConversionCoordinator().clearCompletedJobs();
                    _loadHistory();
                  },
                  child: const Text('Clear Completed', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final job in queue)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getCategoryIcon(job.sourceFile.formatInfo.category),
                            size: 20,
                            color: Color(job.sourceFile.formatInfo.colorValue),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${job.sourceFile.name}.${job.sourceFile.extension} → .${job.targetFormat}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildJobStatusBadge(job),
                        ],
                      ),
                      if (job.status == JobStatus.processing) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: job.progress, minHeight: 4),
                      ],
                      if (job.status == JobStatus.completed && job.resultFilePath != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('Open File', style: TextStyle(fontSize: 12)),
                              onPressed: () => StorageService().openFile(job.resultFilePath!),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.folder_open, size: 14),
                              label: const Text('Show in Folder', style: TextStyle(fontSize: 12)),
                              onPressed: () => StorageService().showInFileManager(job.resultFilePath!),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildJobStatusBadge(ConversionJob job) {
    switch (job.status) {
      case JobStatus.queued:
        return const Text('Queued', style: TextStyle(fontSize: 11, color: Colors.orange));
      case JobStatus.processing:
        return Text('${(job.progress * 100).toInt()}%', style: const TextStyle(fontSize: 11, color: AppTheme.primaryCyan));
      case JobStatus.completed:
        return const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green);
      case JobStatus.failed:
        return const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }

  IconData _getCategoryIcon(FileCategory category) {
    switch (category) {
      case FileCategory.image:
        return Icons.image_rounded;
      case FileCategory.pdf:
        return Icons.picture_as_pdf_rounded;
      case FileCategory.document:
        return Icons.description_rounded;
      case FileCategory.spreadsheet:
        return Icons.table_chart_rounded;
      case FileCategory.presentation:
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _buildCategoryGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildCategoryCard('Image Studio', 'JPG, PNG, WEBP, Crop, Compress', Icons.image_outlined, Colors.blue),
        _buildCategoryCard('PDF Suite', 'Merge, Split, Extract, Watermark', Icons.picture_as_pdf_outlined, Colors.redAccent),
        _buildCategoryCard('Word Documents', 'DOCX, DOC, ODT to PDF', Icons.description_outlined, Colors.indigo),
        _buildCategoryCard('Spreadsheets', 'XLSX, XLS, CSV to Table PDF', Icons.table_chart_outlined, Colors.green),
      ],
    );
  }

  Widget _buildCategoryCard(String title, String subtitle, IconData icon, Color color) {
    return Card(
      child: InkWell(
        onTap: _pickFiles,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentHistoryList() {
    if (_recentHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'No conversions yet. Drop a file above to begin.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final item in _recentHistory)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
              title: Text(
                '${item.sourceName}.${item.sourceFormat} → .${item.targetFormat}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Text(
                '${FileUtils.formatBytes(item.fileSizeBytes)} • ${item.targetPath}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    onPressed: () => StorageService().openFile(item.targetPath),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open, size: 16),
                    onPressed: () => StorageService().showInFileManager(item.targetPath),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
