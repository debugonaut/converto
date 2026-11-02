import 'dart:io';
import 'dart:async';
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/ui/widgets/file_preview_view.dart';
import 'package:converto/ui/widgets/crop_overlay.dart';
import 'package:converto/ui/widgets/image_edit_preview.dart';
import 'package:converto/models/edit_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/local_preview_service.dart';
import 'package:converto/ui/screens/tool_workspace.dart';
import 'package:converto/ui/widgets/output_name_field.dart';
import 'package:converto/ui/widgets/pdf_page_controls.dart';
import 'package:converto/ui/widgets/workspace_results.dart';

void main() {
  for (final size in [const Size(1180, 840), const Size(390, 844)]) {
    testWidgets('image PDF output mode, naming and order work at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scratch = Directory.systemTemp.createTempSync('images-pdf-ui-');
      var paths = List.generate(2, (index) {
        final file = File('${scratch.path}/photo-$index.jpg')
          ..writeAsBytesSync(img.encodeJpg(img.Image(width: 20, height: 12)));
        return file.path;
      });
      final originalPaths = List.of(paths);
      final job = _RecordingJobController();
      final previews = LocalPreviewService(
        renderer: (path, page, dimension, password) async =>
            FilePreview(path: path, kind: 'image', width: 20, height: 12),
      );
      addTearDown(job.dispose);
      addTearDown(previews.dispose);
      addTearDown(() => scratch.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ToolWorkspace(
                tool: ToolDefinition.byId(ToolId.convert),
                paths: paths,
                job: job,
                outputDirectory: scratch.path,
                remember: false,
                previews: previews,
                onBack: () {},
                onPick: () async {},
                onChooseOutput: () async {},
                onPathsChanged: (next) => setState(() => paths = next),
                onOpen: (_, {bool reveal = false}) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder names() => find.descendant(
        of: find.byType(OutputNameField),
        matching: find.byType(TextField),
      );
      expect(names(), findsOneWidget);
      await tester.enterText(names(), 'My photos');
      await tester.ensureVisible(find.byTooltip('Move down').first);
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();
      expect(paths, originalPaths.reversed.toList());
      await tester.ensureVisible(find.text('One combined PDF').first);
      await tester.tap(find.text('One combined PDF').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Separate PDFs').last);
      await tester.pumpAndSettle();
      expect(names(), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('run-tool')));
      await tester.pumpAndSettle();
      expect(job.request!.combinesImagesToPdf, isFalse);
      expect(job.request!.outputNames.keys, paths);
      expect(job.request!.outputName, isNull);
      await tester.ensureVisible(names().first);
      await tester.enterText(names().first, '../invalid');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('run-tool')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Separate PDFs').first);
      await tester.tap(find.text('Separate PDFs').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('One combined PDF').last);
      await tester.pumpAndSettle();
      expect(names(), findsOneWidget);
      expect(tester.widget<TextField>(names()).controller!.text, 'My photos');
      await tester.tap(find.byKey(const Key('run-tool')));
      await tester.pumpAndSettle();
      expect(job.request!.combinesImagesToPdf, isTrue);
      expect(job.request!.paths, paths);
      expect(job.request!.outputName, 'My photos');
      expect(job.request!.outputNames, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'renaming is inline and invalid names disable Run before processing',
    (tester) async {
      final scratch = Directory.systemTemp.createTempSync('name-ui-');
      final image = File('${scratch.path}/image.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 12)));
      final job = GuiJobController();
      addTearDown(job.dispose);
      addTearDown(() => scratch.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ToolWorkspace(
              tool: ToolDefinition.byId(ToolId.convert),
              paths: [image.path],
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
      final field = find.descendant(
        of: find.byType(OutputNameField),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      await tester.enterText(field, '../escape');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('run-tool')))
            .onPressed,
        isNull,
      );
      await tester.enterText(field, 'My invoice');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('run-tool')))
            .onPressed,
        isNotNull,
      );
      expect(job.busy, isFalse);
      expect(job.result, isNull);
      expect(scratch.listSync().length, 1);
    },
  );

  testWidgets('visual page actions preserve order, rotations and reset', (
    tester,
  ) async {
    final expression = TextEditingController(text: '1,2,3');
    final service = LocalPreviewService();
    addTearDown(expression.dispose);
    addTearDown(service.dispose);
    List<int>? rotations;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: PdfPageControls(
            path: '/tmp/preview-fixture.pdf',
            pageCount: 3,
            service: service,
            expression: expression,
            organize: true,
            onRotations: (value) => rotations = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move page right').first);
    await tester.pumpAndSettle();
    expect(expression.text, '2,1,3');
    await tester.tap(find.byTooltip('Duplicate page 1'));
    await tester.pumpAndSettle();
    expect(expression.text, '2,1,1,3');
    await tester.tap(find.byTooltip('Rotate page 2'));
    await tester.pumpAndSettle();
    expect(rotations!.first, 90);
    await tester.tap(find.text('Reset pages'));
    await tester.pumpAndSettle();
    expect(expression.text, '1,2,3');
    expect(rotations, [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page selection updates the actual export expression', (
    tester,
  ) async {
    final expression = TextEditingController();
    final service = LocalPreviewService();
    addTearDown(expression.dispose);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: PdfPageControls(
            path: '/tmp/preview-fixture.pdf',
            pageCount: 3,
            service: service,
            expression: expression,
            selectable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(expression.text, '1,3');
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(expression.text, isEmpty);
  });

  testWidgets('completed results can be sent directly into a compatible tool', (
    tester,
  ) async {
    final service = LocalPreviewService();
    addTearDown(service.dispose);
    ToolDefinition? selected;
    List<String>? paths;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceResults(
            result: const GuiResult(['/tmp/result.pdf'], []),
            tool: ToolId.merge,
            previews: service,
            onOpen: (_, {bool reveal = false}) async {},
            onContinue: (tool, values) {
              selected = tool;
              paths = values;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use result in…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress PDF'));
    await tester.pumpAndSettle();
    expect(selected!.id, ToolId.compress);
    expect(paths, ['/tmp/result.pdf']);
  });
  testWidgets(
    'batch layout and preview dialog support the minimum Mac window and large text',
    (tester) async {
      tester.view.physicalSize = const Size(780, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scratch = Directory.systemTemp.createTempSync('layout-ui-');
      final files = List.generate(
        2,
        (i) => File('${scratch.path}/A long example name with spaces $i.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 20, height: 12))),
      );
      final job = GuiJobController();
      final previews = LocalPreviewService(
        renderer: (path, page, dimension, password) async =>
            FilePreview(path: path, kind: 'image', width: 20, height: 12),
      );
      addTearDown(job.dispose);
      addTearDown(previews.dispose);
      addTearDown(() => scratch.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ToolWorkspace(
              tool: ToolDefinition.byId(ToolId.convert),
              paths: files.map((e) => e.path).toList(),
              job: job,
              outputDirectory: scratch.path,
              remember: false,
              previews: previews,
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
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Expand preview'));
      await tester.tap(find.byTooltip('Expand preview'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'preview rebuilds do not rerender and refresh discards stale metadata',
    (tester) async {
      final scratch = Directory.systemTemp.createTempSync('refresh-ui-');
      final source = File('${scratch.path}/image.png')..writeAsBytesSync([0]);
      final pending = Completer<FilePreview>();
      var calls = 0;
      final service = LocalPreviewService(
        renderer: (path, page, dimension, password) {
          calls++;
          if (calls == 1) return pending.future;
          return Future.value(FilePreview(path: path, width: 22));
        },
      );
      addTearDown(service.dispose);
      addTearDown(() => scratch.deleteSync(recursive: true));
      final metadata = <double>[];
      Future<void> show(int token) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: 300,
              child: FilePreviewView(
                path: source.path,
                service: service,
                reloadToken: token,
                onMetadata: (data) => metadata.add(data.width),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }

      await show(0);
      await show(0);
      expect(calls, 1);
      service.clear();
      await show(1);
      pending.complete(FilePreview(path: source.path, width: 11));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(metadata, [22]);
    },
  );

  testWidgets('visual crop drag yields a bounded nonempty export rectangle', (
    tester,
  ) async {
    Rect value = const Rect.fromLTWH(0, 0, 1, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: StatefulBuilder(
              builder: (context, update) => CropOverlay(
                rectangle: value,
                onChanged: (next) => update(() => value = next),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    final area = tester.getRect(find.byType(CropOverlay));
    final gesture = await tester.startGesture(
      area.topLeft + const Offset(80, 60),
    );
    await gesture.moveTo(area.topLeft + const Offset(300, 220));
    await gesture.moveBy(const Offset(5, 5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(value.width, greaterThan(0));
    expect(value.width, lessThan(1));
    expect(value.left, greaterThanOrEqualTo(0));
    expect(value.right, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'real image edit preview applies rotation crop and resize without processing the input',
    (tester) async {
      final bytes = img.encodePng(img.Image(width: 64, height: 48));
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 300,
            child: ImageEditPreview(
              source: FilePreview(
                path: '/local/image.png',
                kind: 'image',
                width: 64,
                height: 48,
                image: bytes,
              ),
              options: ImageEditOptions(
                rotationDegrees: 90,
                cropX: 2,
                cropY: 3,
                cropWidth: 20,
                cropHeight: 30,
                targetWidth: 10,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('10 × 15 px output'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      final actual = img.decodePng((image.image as MemoryImage).bytes)!;
      expect([actual.width, actual.height], [10, 15]);
      final original = img.decodePng(bytes)!;
      expect([original.width, original.height], [64, 48]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching batch preview retains the visible per-page rotation plan',
    (tester) async {
      final expression = TextEditingController(text: '2,1');
      final service = LocalPreviewService();
      addTearDown(expression.dispose);
      addTearDown(service.dispose);
      Future<void> show(String path) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PdfPageControls(
                path: path,
                pageCount: 2,
                service: service,
                expression: expression,
                organize: true,
                rotations: const [90, 180],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('/tmp/first.pdf');
      expect(
        tester
            .widgetList<RotatedBox>(find.byType(RotatedBox))
            .map((e) => e.quarterTurns),
        [1, 2],
      );
      await show('/tmp/second.pdf');
      expect(
        tester
            .widgetList<RotatedBox>(find.byType(RotatedBox))
            .map((e) => e.quarterTurns),
        [1, 2],
      );
      // Manually editing the page expression intentionally resets visual rotations.
      expression.text = '1,2';
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<RotatedBox>(find.byType(RotatedBox))
            .map((e) => e.quarterTurns),
        [0, 0],
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _RecordingJobController extends GuiJobController {
  GuiRequest? request;
  @override
  Future<void> run(GuiRequest request, {bool remember = true}) async {
    this.request = request;
  }
}
