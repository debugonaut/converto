import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/local_preview_service.dart';
import 'package:converto/ui/screens/tool_workspace.dart';
import 'package:converto/ui/widgets/output_name_field.dart';
import 'package:converto/ui/widgets/scan_preview.dart';

void main() {
  for (final (size, platform, scale) in [
    (const Size(1180, 840), TargetPlatform.macOS, 1.0),
    (const Size(390, 844), TargetPlatform.android, 1.3),
  ]) {
    testWidgets('scan controls, live preview and reset work on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scratch = Directory.systemTemp.createTempSync('scan-ui-');
      final pdf = File(
        'test_assets/notes.pdf',
      ).copySync('${scratch.path}/notes.pdf');
      final photo = File('${scratch.path}/photo.jpg')..writeAsBytesSync([0]);
      final job = _RecordingJob();
      final previews = LocalPreviewService(
        renderer: (path, page, dimension, password) async {
          final image = img.Image(width: 64, height: 48);
          final shade = 80 + page * 100;
          img.fill(image, color: img.ColorRgb8(shade, shade, shade));
          return FilePreview(
            path: path,
            kind: path == pdf.path ? 'pdf' : 'image',
            page: page,
            pageCount: path == pdf.path ? 2 : 1,
            width: 120,
            height: 180,
            image: img.encodePng(image),
          );
        },
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
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ToolWorkspace(
              tool: ToolDefinition.byId(ToolId.scanPdf),
              paths: [pdf.path, photo.path],
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
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
        }
      }

      await settle();
      final name = find.descendant(
        of: find.byType(OutputNameField),
        matching: find.byType(TextField),
      );
      expect(name, findsOneWidget);
      await tester.enterText(name, 'Scan collection');
      expect(find.byType(ScanPreview), findsOneWidget);
      num previewValue() {
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byType(ScanPreview),
            matching: find.byType(Image),
          ),
        );
        final decoded = img.decodePng((image.image as MemoryImage).bytes)!;
        return decoded.getPixel(20, 20).r;
      }

      final originalPreview = previewValue();
      final contrast = find.byKey(const ValueKey('scan-contrast'));
      await tester.ensureVisible(contrast);
      tester.widget<Slider>(contrast).onChanged!(2);
      await settle();
      expect(previewValue(), lessThan(originalPreview));
      expect(find.text('200%'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Next page'));
      await settle();
      expect(previewValue(), greaterThan(200));
      expect(tester.widget<Slider>(contrast).value, 2);
      await tester.ensureVisible(find.text('Show original'));
      await tester.tap(find.text('Show original'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanPreview), findsNothing);
      await tester.tap(find.text('Show original'));
      await settle();
      await tester.ensureVisible(find.byTooltip('Expand preview'));
      await tester.tap(find.byTooltip('Expand preview'));
      await settle();
      expect(find.byType(ScanPreview), findsNWidgets(2));
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Grayscale').first);
      await tester.tap(find.text('Grayscale').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black and white').last);
      await settle();
      final threshold = find.byKey(const ValueKey('scan-threshold'));
      expect(threshold, findsOneWidget);
      tester.widget<Slider>(threshold).onChanged!(.4);
      await tester.tap(find.byKey(const Key('run-tool')));
      await tester.pumpAndSettle();
      expect(job.request!.tool, ToolId.scanPdf);
      expect(job.request!.paths, [pdf.path, photo.path]);
      expect(job.request!.outputName, 'Scan collection');
      expect(job.request!.outputNames, isEmpty);
      expect(job.request!.options['contrast'], 2);
      expect(job.request!.options['threshold'], .4);
      expect(job.request!.options['scanMode'], 'blackAndWhite');
      expect(job.request!.hasCombinedOutput, isTrue);
      await tester.ensureVisible(find.text('Reset options'));
      await tester.tap(find.text('Reset options'));
      await settle();
      expect(tester.widget<Slider>(contrast).value, 1.2);
      expect(threshold, findsNothing);
      expect(find.text('Grayscale'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Previewing and changing settings never saves or changes a source file.
      expect(scratch.listSync().length, 2);
    }, variant: TargetPlatformVariant.only(platform));
  }
}

class _RecordingJob extends GuiJobController {
  GuiRequest? request;
  @override
  Future<void> run(GuiRequest request, {bool remember = true}) async {
    this.request = request;
  }
}
