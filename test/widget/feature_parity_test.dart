import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/local_preview_service.dart';
import 'package:converto/services/gui/secondary_file_picker.dart';
import 'package:converto/services/gui/tool_capabilities.dart';
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/ui/screens/tool_workspace.dart';

class RecordingJob extends GuiJobController {
  GuiRequest? last;
  @override
  Future<void> run(GuiRequest request, {bool remember = true}) async {
    last = request;
    result = const GuiResult([], []);
    notifyListeners();
  }
}

void main() {
  test('primary action typography follows the native app font', () {
    final theme = AppTheme.darkTheme;
    expect(
      theme.filledButtonTheme.style!.textStyle!.resolve({})!.fontFamily,
      theme.textTheme.bodyMedium!.fontFamily,
    );
  });
  late Directory temp;
  late File input;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('parity-widget-');
    input = File('${temp.path}/input.pdf')..writeAsStringSync('%PDF-test');
  });
  tearDown(() => temp.deleteSync(recursive: true));
  const desktop = ToolCapabilities(
    mobile: false,
    libreOffice: true,
    webp: true,
    tesseract: true,
  );
  const mobile = ToolCapabilities(
    mobile: true,
    libreOffice: false,
    webp: false,
    tesseract: false,
  );
  Future<void> mount(
    WidgetTester tester,
    ToolId tool, {
    List<String>? paths,
    ToolCapabilities capabilities = desktop,
    RecordingJob? job,
    double textScale = 1,
    Future<PickedLocalFile?> Function(List<String>)? picker,
  }) async {
    final controller = job ?? RecordingJob();
    addTearDown(controller.dispose);
    final previews = LocalPreviewService(
      renderer: (path, page, dimension, password) async => FilePreview(
        path: path,
        kind: 'pdf',
        pageCount: 2,
        width: 240,
        height: 320,
      ),
    );
    addTearDown(previews.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ToolWorkspace(
            key: ValueKey('$tool-${paths?.length}'),
            tool: ToolDefinition.byId(tool),
            paths: paths ?? [input.path],
            job: controller,
            previews: previews,
            capabilities: capabilities,
            secondaryPicker: picker,
            outputDirectory: '${temp.path}/out',
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
  }

  FilledButton run(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('run-tool')));
  testWidgets('comparison needs exactly two files and one HTML output name', (
    tester,
  ) async {
    await mount(tester, ToolId.compare);
    expect(run(tester).onPressed, isNull);
    expect(find.textContaining('exactly two PDFs'), findsOneWidget);
    final other = input.copySync('${temp.path}/other.pdf');
    await mount(tester, ToolId.compare, paths: [input.path, other.path]);
    expect(run(tester).onPressed, isNotNull);
    expect(find.textContaining('.html'), findsWidgets);
  });
  testWidgets('mobile OCR has an honest unavailable state before Run', (
    tester,
  ) async {
    await mount(tester, ToolId.ocr, capabilities: mobile);
    expect(run(tester).onPressed, isNull);
    expect(find.textContaining('not bundled on mobile'), findsOneWidget);
  });
  testWidgets('the certificate picker is visible before the phone preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, ToolId.sign, capabilities: mobile);
    expect(
      tester.getBottomLeft(find.text('Choose certificate')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('run-tool'))).dy),
    );
  });
  testWidgets('split and extraction modes only validate their active fields', (
    tester,
  ) async {
    await mount(tester, ToolId.split);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target file size').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Target size (MB)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pages per part'), findsNothing);
    await mount(tester, ToolId.pdfImages);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract embedded images').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Resolution (DPI)'), findsNothing);
    expect(run(tester).onPressed, isNotNull);
  });
  testWidgets(
    'certificate cancellation preserves selection and a run clears secrets',
    (tester) async {
      var selected = 0, released = 0;
      final key = File('${temp.path}/private.p12')
        ..writeAsStringSync('synthetic');
      final job = RecordingJob();
      await mount(
        tester,
        ToolId.sign,
        job: job,
        picker: (_) async => ++selected == 1
            ? PickedLocalFile(
                key.path,
                release: () async {
                  released++;
                },
              )
            : null,
      );
      expect(run(tester).onPressed, isNull);
      await tester.ensureVisible(find.text('Choose certificate'));
      await tester.tap(find.text('Choose certificate'));
      await tester.pumpAndSettle();
      expect(find.text('private.p12'), findsOneWidget);
      expect(run(tester).onPressed, isNotNull);
      await tester.tap(find.text('Change certificate'));
      await tester.pumpAndSettle();
      expect(find.text('private.p12'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Certificate password'),
        'test secret',
      );
      await tester.ensureVisible(find.byKey(const Key('run-tool')));
      await tester.tap(find.byKey(const Key('run-tool')));
      await tester.pumpAndSettle();
      expect(job.last!.options['certificatePassword'], 'test secret');
      expect(released, 1);
      expect(find.text('private.p12'), findsNothing);
      expect(find.text('test secret'), findsNothing);
      expect(run(tester).onPressed, isNull);
    },
  );
  testWidgets('new controls fit a narrow phone at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final tool in [
      ToolId.compare,
      ToolId.repair,
      ToolId.clean,
      ToolId.sign,
      ToolId.ocr,
      ToolId.flatten,
      ToolId.watermark,
      ToolId.pageNumbers,
    ]) {
      await mount(tester, tool, capabilities: mobile, textScale: 2);
      expect(tester.takeException(), isNull, reason: tool.name);
    }
  });
}
