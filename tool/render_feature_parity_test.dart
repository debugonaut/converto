// Offscreen Flutter captures of synthetic local files, not physical-device QA.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/models/gui/file_preview.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/local_preview_service.dart';
import 'package:converto/services/gui/secondary_file_picker.dart';
import 'package:converto/services/gui/tool_capabilities.dart';
import 'package:converto/services/pdf/pdf_engine.dart';
import 'package:converto/ui/screens/tool_workspace.dart';

void main() {
  testWidgets(
    'render approved native feature controls and actual watermark output',
    (tester) async {
      final folder = Directory('build/audit/parity-renders')
        ..createSync(recursive: true);
      final font = File('/System/Library/Fonts/SFNS.ttf');
      if (font.existsSync())
        for (final family in ['.AppleSystemUIFont', 'Roboto', 'Ahem']) {
          await (FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
        }
      final icons = File(
        p.join(
          p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
          'material_fonts',
          'MaterialIcons-Regular.otf',
        ),
      );
      if (icons.existsSync())
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            ))
            .load();
      final first = File('${folder.absolute.path}/sample.pdf'),
          second = File('${folder.absolute.path}/revised.pdf'),
          logo = File('${folder.absolute.path}/logo.png');
      late FilePreview sample;
      await tester.runAsync(() async {
        final pdf = pw.Document();
        for (var i = 1; i <= 2; i++) {
          pdf.addPage(
            pw.Page(
              pageFormat: const PdfPageFormat(240, 320),
              margin: const pw.EdgeInsets.all(24),
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Project notes',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text('A document that stays on your device.\n\nPage $i'),
                ],
              ),
            ),
          );
        }
        first.writeAsBytesSync(await pdf.save());
        second.writeAsBytesSync(first.readAsBytesSync());
        logo.writeAsBytesSync(
          img.encodePng(
            img.fill(
              img.Image(width: 80, height: 40),
              color: img.ColorRgb8(40, 115, 100),
            ),
          ),
        );
        final raster = await PdfEngine.rasterizePages(
          sourceFile: first,
          dpi: 96,
        ).first;
        sample = FilePreview(
          path: first.path,
          kind: 'pdf',
          pageCount: 2,
          width: 240,
          height: 320,
          image: raster.png,
          rasterWidth: 320,
          rasterHeight: 427,
        );
      });
      final job = GuiJobController();
      addTearDown(job.dispose);
      addTearDown(PdfEngine.dispose);
      final previews = LocalPreviewService(
        renderer: (path, page, dimension, password) async => FilePreview(
          path: path,
          page: page,
          kind: sample.kind,
          pageCount: 2,
          width: sample.width,
          height: sample.height,
          image: sample.image,
          rasterWidth: sample.rasterWidth,
          rasterHeight: sample.rasterHeight,
        ),
      );
      addTearDown(previews.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Future<void> capture(String name, GlobalKey boundary) async {
        await tester.runAsync(() async {
          final bitmap =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${folder.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
      }

      for (final (size, scale, platform, label) in [
        (const Size(390, 844), 1.0, TargetPlatform.android, 'phone'),
        (const Size(1180, 900), 1.0, TargetPlatform.macOS, 'desktop'),
        (const Size(390, 844), 2.0, TargetPlatform.android, 'phone-large'),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final tool in [
          ToolId.compare,
          ToolId.clean,
          ToolId.sign,
          ToolId.ocr,
          ToolId.watermark,
        ]) {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: ToolWorkspace(
                    key: ValueKey('$label-$tool'),
                    tool: ToolDefinition.byId(tool),
                    paths: [
                      first.path,
                      if (tool == ToolId.compare) second.path,
                    ],
                    job: job,
                    previews: previews,
                    capabilities: ToolCapabilities(
                      mobile: platform == TargetPlatform.android,
                      libreOffice: false,
                      webp: false,
                      tesseract: platform != TargetPlatform.android,
                    ),
                    secondaryPicker: (_) async => PickedLocalFile(logo.path),
                    outputDirectory: folder.path,
                    remember: false,
                    onBack: () {},
                    onPick: () async {},
                    onChooseOutput: () async {},
                    onPathsChanged: (_) {},
                    onOpen: (_, {bool reveal = false}) async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          if (tool == ToolId.watermark) {
            await tester.ensureVisible(
              find.widgetWithText(TextField, 'Watermark text'),
            );
            await tester.enterText(
              find.widgetWithText(TextField, 'Watermark text'),
              'DRAFT',
            );
            await tester.pump(const Duration(milliseconds: 400));
            for (var i = 0; i < 15; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 80)),
              );
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(find.textContaining('Preview unavailable'), findsNothing);
            if (label == 'desktop') {
              await tester.tap(find.byTooltip('Next page'));
              await tester.pump(const Duration(milliseconds: 450));
              for (var i = 0; i < 10; i++) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 70)),
                );
                await tester.pump(const Duration(milliseconds: 50));
              }
              expect(find.text('Page 2 · exported appearance'), findsOneWidget);
            }
          }
          await capture('$label-${tool.name}-options', boundary);
          if (tool == ToolId.watermark) {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, 2000),
            );
            await tester.pumpAndSettle();
            await capture('$label-watermark-preview', boundary);
          }
          expect(tester.takeException(), isNull, reason: '$label-${tool.name}');
        }
      }
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpAndSettle();
    },
  );
}
