import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/format_types.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/tool_definition.dart';
import '../../services/gui/file_intake.dart';
import '../../services/gui/gui_job_controller.dart';
import '../../services/gui/gui_preferences.dart';
import '../../services/gui/local_preview_service.dart';
import '../../services/history_service.dart';
import '../../services/local_process.dart';
import '../../services/storage_service.dart';
import '../tool_icons.dart';
import 'tool_workspace.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});
  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _preferences = GuiPreferences();
  final _job = GuiJobController();
  final _previews = LocalPreviewService();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<String> _paths = [];
  ToolDefinition? _tool;
  ToolCategory _category = ToolCategory.all;
  bool _recent = false;
  bool _dragging = false;
  int _pendingIntakes = 0;
  int _intakeRevision = 0;
  String _query = '';
  Future<void> _intakeTail = Future.value();

  @override
  void initState() {
    super.initState();
    _job.addListener(_refresh);
    _load();
  }

  Future<void> _load() async {
    await _preferences.load();
    await HistoryService().init();
    if (_preferences.outputDirectory == null) {
      _preferences.outputDirectory =
          (await StorageService().getOutputDirectory()).path;
    }
    _refresh();
  }

  void _refresh() {
    _previews.paused = _job.busy;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _job.removeListener(_refresh);
    _job.dispose();
    _previews.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _intake(Iterable<String> paths) {
    if (_job.busy || !mounted) return Future.value();
    final batch = paths.toList();
    setState(() => _pendingIntakes++);
    _intakeTail = _intakeTail
        .then((_) async {
          if (!mounted || _job.busy) return;
          final result = await FileIntake.collect(batch, existing: _paths);
          if (!mounted || _job.busy) return;
          setState(() {
            _paths = result.paths.toList();
            _intakeRevision++;
            _recent = false;
          });
          if (result.issues.isNotEmpty)
            _notice(result.issues.take(3).join('\n'));
        })
        .catchError((Object error) {
          _notice('Could not add files: $error');
        })
        .whenComplete(() {
          if (mounted) setState(() => _pendingIntakes--);
        });
    return _intakeTail;
  }

  Future<void> _pick() async {
    if (_job.busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: FormatRegistry.allSupportedExtensions,
        dialogTitle: 'Choose files to work with',
      );
      if (result != null) await _intake(result.paths.whereType<String>());
    } catch (e) {
      _notice('Could not choose files: $e');
    }
  }

  Future<void> _chooseOutput() async {
    try {
      final folder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Save results to',
      );
      if (folder == null || !mounted) return;
      setState(() => _preferences.outputDirectory = folder);
      await _preferences.save();
    } catch (e) {
      _notice('Could not set output folder: $e');
    }
  }

  Future<void> _open(String path, {bool reveal = false}) async {
    try {
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        _notice('This file has been moved or deleted.');
        return;
      }
      if (reveal) {
        await FileUtils.revealInFileManager(path);
      } else {
        await FileUtils.openFile(path);
      }
    } catch (e) {
      _notice('Could not open this file: $e');
    }
  }

  Future<void> _settings() async {
    final capabilities = await PlatformDetector.detect();
    final webp = LocalProcess.find('cwebp');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Output folder',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _preferences.outputDirectory ?? 'Loading…',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                TextButton(
                  onPressed: () async {
                    await _chooseOutput();
                    update(() {});
                  },
                  child: const Text('Choose folder'),
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remember recent results'),
                  subtitle: const Text(
                    'File names and paths are saved only on this Mac.',
                  ),
                  value: _preferences.rememberHistory,
                  onChanged: (value) async {
                    update(() => _preferences.rememberHistory = value);
                    await _preferences.save();
                  },
                ),
                TextButton(
                  onPressed: () async {
                    await HistoryService().clearHistory();
                    _refresh();
                    _notice('Local history cleared. Your files are unchanged.');
                  },
                  child: const Text('Clear local history'),
                ),
                const Divider(),
                const SizedBox(height: 18),
                const Text(
                  'Local engines',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('PDF & image processing: built in'),
                Text(
                  'LibreOffice: ${capabilities.hasLibreOfficeCLI ? 'available' : 'not installed (optional)'}',
                ),
                Text(
                  'WebP encoder: ${webp != null ? 'available' : 'not installed (optional)'}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Optional helpers are never downloaded automatically. Some Office inputs and WebP output need a local helper.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _cli() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Use the CLI'),
      content: const SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The app and CLI use the same local processing engine. If the Converto CLI is installed, run this in Terminal:',
            ),
            SizedBox(height: 18),
            SelectableText(
              'converto help',
              style: TextStyle(fontFamily: 'Menlo', color: AppTheme.amber),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: 'converto help'));
            if (context.mounted) Navigator.pop(context);
            _notice('CLI command copied.');
          },
          child: const Text('Copy command'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final extensions = _paths.map(FileUtils.getExtension).toSet();
    final tools = ToolDefinition.tools
        .where(
          (tool) =>
              (_category == ToolCategory.all || tool.category == _category) &&
              '${tool.title} ${tool.description}'.toLowerCase().contains(
                _query,
              ) &&
              extensions.every(tool.accepts),
        )
        .toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _pick,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          if (_tool == null) _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_job.busy) setState(() => _tool = null);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 26),
                      const SizedBox(width: 10),
                      const Text(
                        'Converto',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(width: 40),
                      _nav(
                        'Tools',
                        !_recent,
                        () => setState(() {
                          _recent = false;
                          _tool = null;
                        }),
                      ),
                      const SizedBox(width: 12),
                      _nav(
                        'Recent',
                        _recent,
                        () => setState(() {
                          _recent = true;
                          _tool = null;
                        }),
                      ),
                      const Spacer(),
                      const Icon(Icons.circle, size: 7, color: AppTheme.teal),
                      const SizedBox(width: 7),
                      const Text(
                        'Offline',
                        style: TextStyle(color: AppTheme.teal, fontSize: 12),
                      ),
                      const SizedBox(width: 18),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: _job.busy ? null : _settings,
                        icon: const Icon(Icons.settings_outlined, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: DropTarget(
                    enable: !_job.busy,
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (details) {
                      setState(() => _dragging = false);
                      _intake(details.files.map((file) => file.path));
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _recent
                              ? _recentView()
                              : _tool == null
                              ? _hub(tools)
                              : ToolWorkspace(
                                  key: ValueKey(_tool!.id),
                                  tool: _tool!,
                                  paths: _paths,
                                  job: _job,
                                  outputDirectory: _preferences.outputDirectory,
                                  remember: _preferences.rememberHistory,
                                  addingFiles: _pendingIntakes > 0,
                                  previews: _previews,
                                  intakeRevision: _intakeRevision,
                                  onUseResults: (tool, paths) {
                                    _job.reset();
                                    setState(() {
                                      _paths = List.of(paths);
                                      _tool = tool;
                                      _recent = false;
                                    });
                                  },
                                  onBack: () => setState(() => _tool = null),
                                  onPick: _pick,
                                  onChooseOutput: _chooseOutput,
                                  onPathsChanged: (paths) =>
                                      setState(() => _paths = paths),
                                  onOpen: _open,
                                ),
                        ),
                        if (_dragging)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                margin: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.background.withValues(
                                    alpha: .96,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.amber,
                                    width: 2,
                                  ),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.file_download_outlined,
                                        size: 40,
                                        color: AppTheme.amber,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Drop files to add them',
                                        style: TextStyle(fontSize: 22),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Choose a tool when you’re ready.',
                                        style: TextStyle(color: AppTheme.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Files stay on this device.',
                        style: TextStyle(fontSize: 12, color: AppTheme.muted),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _cli,
                        child: const Text(
                          'Use CLI',
                          style: TextStyle(fontSize: 12, color: AppTheme.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav(String label, bool selected, VoidCallback action) => TextButton(
    onPressed: _job.busy || _pendingIntakes > 0 ? null : action,
    style: TextButton.styleFrom(
      foregroundColor: selected ? AppTheme.amber : AppTheme.muted,
    ),
    child: Text(label),
  );
  Widget _hub(List<ToolDefinition> tools) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          compact ? 28 : 52,
          30,
          compact ? 28 : 52,
          36,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tools for your files.',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 9),
                          const Text(
                            'Convert, edit, and organize. All on your device.',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) const SizedBox(width: 32),
                    if (!compact) SizedBox(width: 270, child: _searchField()),
                  ],
                ),
                if (compact) ...[const SizedBox(height: 22), _searchField()],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _paths.isEmpty
                            ? Icons.file_download_outlined
                            : Icons.check_circle_outline,
                        color: _paths.isEmpty ? AppTheme.muted : AppTheme.teal,
                        size: 24,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _paths.isEmpty
                              ? 'Drop files to see compatible tools'
                              : '${_paths.length} files selected · showing compatible tools',
                        ),
                      ),
                      if (_paths.isNotEmpty)
                        TextButton(
                          onPressed: _pendingIntakes > 0
                              ? null
                              : () => setState(() => _paths = []),
                          child: const Text('Clear'),
                        ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _pick,
                        child: Text(
                          _paths.isEmpty ? 'Choose files' : 'Add files',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 21),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: ToolCategory.values
                      .map(
                        (category) => ChoiceChip(
                          label: Text(
                            category == ToolCategory.all
                                ? 'All tools'
                                : '${category.name[0].toUpperCase()}${category.name.substring(1)}',
                          ),
                          selected: _category == category,
                          labelStyle: TextStyle(
                            fontFamily: '.AppleSystemUIFont',
                            color: _category == category
                                ? AppTheme.amber
                                : AppTheme.muted,
                          ),
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                if (tools.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No tools match this selection.',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try another search, category or group of files.',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                        TextButton(
                          onPressed: _pendingIntakes > 0
                              ? null
                              : () => setState(() {
                                  _query = '';
                                  _search.clear();
                                  _category = ToolCategory.all;
                                  _paths = [];
                                }),
                          child: const Text('Reset filters'),
                        ),
                      ],
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, grid) {
                    final columns = grid.maxWidth >= 860
                        ? 3
                        : grid.maxWidth >= 540
                        ? 2
                        : 1;
                    final width =
                        (grid.maxWidth - 16 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: tools
                          .map(
                            (tool) => SizedBox(
                              width: width,
                              height: 136,
                              child: Material(
                                color: AppTheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                    color: AppTheme.border,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    _job.reset();
                                    setState(() => _tool = tool);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          toolIcon(tool.id),
                                          size: 27,
                                          color: const Color(0xFFE4DFD4),
                                        ),
                                        const Spacer(),
                                        Text(
                                          tool.title,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          tool.description,
                                          maxLines: 2,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _searchField() => TextField(
    controller: _search,
    focusNode: _searchFocus,
    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    decoration: InputDecoration(
      hintText: 'Find a tool',
      prefixIcon: const Icon(Icons.search, size: 20),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () => setState(() {
                _search.clear();
                _query = '';
              }),
              icon: const Icon(Icons.close, size: 16),
            ),
    ),
  );
  Widget _recentView() {
    final history = HistoryService().getHistory();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 36),
      children: [
        Text(
          'Recent results',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'Saved on this Mac. Your files are never uploaded.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 28),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Your completed files will appear here. Choose a tool to get started.',
            ),
          ),
        for (final item in history)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(
              Icons.description_outlined,
              color: AppTheme.muted,
            ),
            title: Text(p.basename(item.targetPath)),
            subtitle: Text(
              '${item.targetFormat.toUpperCase()} · ${FileUtils.formatBytes(item.fileSizeBytes)} · ${item.timestamp.toLocal().toString().substring(0, 16)}',
            ),
            onTap: () => _open(item.targetPath),
            trailing: IconButton(
              tooltip: 'Show in Finder',
              onPressed: () => _open(item.targetPath, reveal: true),
              icon: const Icon(Icons.folder_open_outlined),
            ),
          ),
      ],
    );
  }
}
