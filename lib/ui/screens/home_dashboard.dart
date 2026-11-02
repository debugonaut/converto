import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/format_types.dart';
import '../../core/platform/platform_detector.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/tool_definition.dart';
import '../../services/gui/file_intake.dart';
import '../../services/gui/mobile_documents.dart';
import '../../services/gui/desktop_file_picker.dart';
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
  bool _documentBusy = false;
  bool get _mobile => MobileDocuments.enabled;
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

  String _errorText(Object error) =>
      error is PlatformException ? error.message ?? error.code : '$error';

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
    if (_job.busy || _pendingIntakes > 0) return;
    setState(() => _pendingIntakes++);
    try {
      final paths = await DesktopFilePicker.pickFiles(
        extensions: FormatRegistry.allSupportedExtensions,
      );
      if (paths != null) await _intake(paths);
    } catch (e) {
      _notice('Could not choose files: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _pendingIntakes--);
    }
  }

  Future<void> _chooseOutput() async {
    try {
      final folder = await DesktopFilePicker.pickDirectory();
      if (folder == null || !mounted) return;
      setState(() => _preferences.outputDirectory = folder);
      await _preferences.save();
    } catch (e) {
      _notice('Could not set output folder: $e');
    }
  }

  Future<void> _open(String path, {bool reveal = false}) async {
    if (_documentBusy) return;
    _documentBusy = true;
    try {
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        _notice('This file has been moved or deleted.');
        return;
      }
      if (_mobile) {
        if (reveal) {
          if (await MobileDocuments.exportFile(path)) _notice('Copy exported.');
        } else {
          await MobileDocuments.openFile(path);
        }
      } else if (reveal) {
        await FileUtils.revealInFileManager(path);
      } else {
        await FileUtils.openFile(path);
      }
    } catch (e) {
      _notice(
        'Could not ${reveal && _mobile ? 'export' : 'open'} this file: ${_errorText(e)}',
      );
    } finally {
      _documentBusy = false;
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_mobile)
                    const Text(
                      'Results are saved privately in this app. Use Export on a completed result to save a copy to your chosen folder. Uninstalling removes private results.',
                    ),
                  if (!_mobile) ...[
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
                  ],
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remember recent results'),
                    subtitle: const Text(
                      'File names and paths are saved only on this device.',
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
                      _notice(
                        'Local history cleared. Your files are unchanged.',
                      );
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
                  if (!_mobile)
                    Text(
                      'LibreOffice: ${capabilities.hasLibreOfficeCLI ? 'available' : 'not installed (optional)'}',
                    ),
                  if (!_mobile)
                    Text(
                      'WebP encoder: ${webp != null ? 'available' : 'not installed (optional)'}',
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _mobile
                        ? 'Desktop helpers (LibreOffice, WebP encoding and OCR) are unavailable on Android. Tools that require them report an explicit error.'
                        : 'Optional helpers are never downloaded automatically. Some Office inputs and WebP output need a local helper.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PopScope(
      canPop: _tool == null && !_recent && !_job.busy && _pendingIntakes == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_job.busy || _pendingIntakes > 0) {
          _notice(
            'Wait for the current operation or cancel it before leaving.',
          );
        } else {
          setState(() {
            _tool = null;
            _recent = false;
          });
        }
      },
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyO,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): _pick,
          SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () {
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
                  if (compact)
                    _compactHeader()
                  else
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
                          const Icon(
                            Icons.circle,
                            size: 7,
                            color: AppTheme.teal,
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            'Offline',
                            style: TextStyle(
                              color: AppTheme.teal,
                              fontSize: 12,
                            ),
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
                    child: _dropTarget(
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
                                    outputDirectory:
                                        _preferences.outputDirectory,
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
                                          style: TextStyle(
                                            color: AppTheme.muted,
                                          ),
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
                  if (_mobile && compact && _tool == null)
                    NavigationBar(
                      selectedIndex: _recent ? 1 : 0,
                      onDestinationSelected: _job.busy || _pendingIntakes > 0
                          ? null
                          : (index) => setState(() {
                              _recent = index == 1;
                              _tool = null;
                            }),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.grid_view_outlined),
                          label: 'Tools',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.history),
                          label: 'Recent',
                        ),
                      ],
                    ),
                  if (!compact || !_mobile) const Divider(),
                  if (!compact || !_mobile)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Files stay on this device.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.muted,
                            ),
                          ),
                          const Spacer(),
                          if (!_mobile)
                            TextButton(
                              onPressed: _cli,
                              child: const Text(
                                'Use CLI',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.muted,
                                ),
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
      ),
    );
  }

  Widget _compactHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Converto',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            const Text(
              'Offline',
              style: TextStyle(color: AppTheme.teal, fontSize: 12),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: _job.busy || _pendingIntakes > 0 ? null : _settings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        if (!_mobile)
          Row(
            children: [
              _nav(
                'Tools',
                !_recent,
                () => setState(() {
                  _recent = false;
                  _tool = null;
                }),
              ),
              _nav(
                'Recent',
                _recent,
                () => setState(() {
                  _recent = true;
                  _tool = null;
                }),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _dropTarget({required Widget child}) => _mobile
      ? child
      : DropTarget(
          enable: !_job.busy,
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            _intake(details.files.map((file) => file.path));
          },
          child: child,
        );

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
          constraints.maxWidth < 600
              ? 16
              : compact
              ? 28
              : 52,
          30,
          constraints.maxWidth < 600
              ? 16
              : compact
              ? 28
              : 52,
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
                              ? (_mobile
                                    ? 'Choose files to see compatible tools'
                                    : 'Drop files to see compatible tools')
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
                              height:
                                  158 +
                                  (MediaQuery.textScalerOf(context).scale(14) -
                                              14)
                                          .clamp(0, 60) *
                                      4,
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
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 52,
        vertical: 28,
      ),
      children: [
        Text(
          'Recent results',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        const Text(
          'Saved on this device. Your files are never uploaded.',
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
            title: Text(
              p.basename(item.targetPath),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${item.targetFormat.toUpperCase()} · ${FileUtils.formatBytes(item.fileSizeBytes)} · ${item.timestamp.toLocal().toString().substring(0, 16)}',
            ),
            onTap: () => _open(item.targetPath),
            trailing: IconButton(
              tooltip: _mobile
                  ? 'Export result'
                  : Platform.isWindows
                  ? 'Show in Explorer'
                  : Platform.isMacOS
                  ? 'Show in Finder'
                  : 'Show in file manager',
              onPressed: () => _open(item.targetPath, reveal: true),
              icon: Icon(_mobile ? Icons.save_alt : Icons.folder_open_outlined),
            ),
          ),
      ],
    );
  }
}
