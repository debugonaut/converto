import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/main.dart';
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/ui/screens/tool_workspace.dart';

void main() {
  testWidgets(
    'hub searches, filters and opens a workspace without processing',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ConvertoApp());
      await tester.pumpAndSettle();
      expect(find.text('Tools for your files.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'watermark');
      await tester.pumpAndSettle();
      expect(find.text('Merge PDF'), findsNothing);
      await tester.tap(find.text('Watermark'));
      await tester.pumpAndSettle();
      expect(find.text('Watermark text'), findsOneWidget);
      final run = tester.widget<FilledButton>(
        find.byKey(const Key('run-tool')),
      );
      expect(run.onPressed, isNull);
      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-a-tool');
      await tester.pumpAndSettle();
      expect(find.text('No tools match this selection.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid repeated drops select once and never auto-run', (
    tester,
  ) async {
    final scratch = Directory.systemTemp.createTempSync('gui-drop-widget-');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final file = File('${scratch.path}/file with spaces.pdf')
      ..writeAsStringSync('test input');
    tester.view.physicalSize = const Size(1180, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ConvertoApp());
    await tester.pumpAndSettle();
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    final drop = DropDoneDetails(
      files: [XFile(file.path)],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    await tester.runAsync(() async {
      target.onDragDone!(drop);
      target.onDragDone!(drop);
      target.onDragDone!(drop);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      find.text('1 files selected · showing compatible tools'),
      findsOneWidget,
    );
    await tester.tap(find.text('Watermark'));
    await tester.pumpAndSettle();
    final workspace = tester.widget<ToolWorkspace>(find.byType(ToolWorkspace));
    expect(workspace.addingFiles, isFalse);
    expect(workspace.job.busy, isFalse);
    expect(workspace.job.result, isNull);
    expect(find.text('file with spaces.pdf'), findsOneWidget);
    expect(scratch.listSync().length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all selected-file workspaces stay idle and fit the compact Mac window',
    (tester) async {
      final scratch = Directory.systemTemp.createTempSync('gui-workspace-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final pdf = File('${scratch.path}/document.pdf')
        ..writeAsStringSync('not processed until Run');
      final image = File('${scratch.path}/image.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 12)));
      tester.view.physicalSize = const Size(780, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final job = GuiJobController();
      addTearDown(job.dispose);
      for (final tool in ToolDefinition.tools) {
        final paths = tool.id == ToolId.editImage
            ? [image.path]
            : tool.id == ToolId.merge
            ? [pdf.path, image.path]
            : [pdf.path];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ToolWorkspace(
                key: ValueKey(tool.id),
                tool: tool,
                paths: paths,
                job: job,
                outputDirectory: scratch.path,
                remember: false,
                onBack: () {},
                onPick: () async {},
                onChooseOutput: () async {},
                onPathsChanged: (_) {},
                onOpen: (_, {bool reveal = false}) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tool.title);
        expect(job.busy, isFalse);
        expect(job.result, isNull);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('run-tool')))
              .onPressed,
          [
                ToolId.organize,
                ToolId.watermark,
                ToolId.protect,
                ToolId.redact,
                ToolId.extract,
                ToolId.crop,
                ToolId.unlock,
              ].contains(tool.id)
              ? isNull
              : isNotNull,
          reason: tool.title,
        );
      }
      expect(scratch.listSync().length, 2);
    },
  );

  testWidgets('large export results use a bounded lazy list', (tester) async {
    final job = GuiJobController();
    addTearDown(job.dispose);
    job.result = GuiResult(
      List.generate(10000, (index) => '/tmp/page-$index.png'),
      const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ToolWorkspace(
            tool: ToolDefinition.byId(ToolId.pdfImages),
            paths: const [],
            job: job,
            outputDirectory: '/tmp/results',
            remember: false,
            onBack: () {},
            onPick: () async {},
            onChooseOutput: () async {},
            onPathsChanged: (_) {},
            onOpen: (_, {bool reveal = false}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('10000 files ready'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Run and file removal stay disabled while a drop batch is being read',
    (tester) async {
      final job = GuiJobController();
      addTearDown(job.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ToolWorkspace(
              tool: ToolDefinition.byId(ToolId.pdfText),
              paths: const ['/tmp/input.pdf'],
              job: job,
              outputDirectory: '/tmp/results',
              remember: false,
              addingFiles: true,
              onBack: () {},
              onPick: () async {},
              onChooseOutput: () async {},
              onPathsChanged: (_) {},
              onOpen: (_, {bool reveal = false}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('run-tool')))
            .onPressed,
        isNull,
      );
      expect(find.text('Adding files…'), findsOneWidget);
      final remove = find.widgetWithIcon(IconButton, Icons.close);
      expect(tester.widget<IconButton>(remove).onPressed, isNull);
      expect(job.busy, isFalse);
    },
  );

  for (final width in [780.0, 1180.0]) {
    testWidgets(
      'every workspace fits a ${width.toInt()}px Mac window with empty states',
      (tester) async {
        tester.view.physicalSize = Size(width, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final job = GuiJobController();
        addTearDown(job.dispose);
        for (final tool in ToolDefinition.tools) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: ToolWorkspace(
                  key: ValueKey(tool.id),
                  tool: tool,
                  paths: const [],
                  job: job,
                  outputDirectory: '/tmp/results',
                  remember: false,
                  onBack: () {},
                  onPick: () async {},
                  onChooseOutput: () async {},
                  onPathsChanged: (_) {},
                  onOpen: (_, {bool reveal = false}) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tool.title);
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('run-tool')))
                .onPressed,
            isNull,
            reason: tool.title,
          );
        }
      },
    );
  }
}
