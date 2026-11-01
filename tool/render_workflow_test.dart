// Offscreen Flutter renders of real local fixtures; not native Finder coverage.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:converto/main.dart';
import 'package:converto/ui/widgets/output_name_field.dart';
import 'package:converto/ui/widgets/workspace_file_list.dart';

void main() {
  if (Platform.environment['CONVERTO_DATA_DIR'] == null ||
      Platform.environment['CONVERTO_OUTPUT_DIR'] == null) {
    throw StateError(
      'Set isolated CONVERTO_DATA_DIR and CONVERTO_OUTPUT_DIR before rendering. See the workflow audit.',
    );
  }

  testWidgets('render populated local file workflows', (tester) async {
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (font.existsSync()) {
      for (final family in ['.AppleSystemUIFont', 'Roboto', 'Arial']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
    }
    final iconFont = File(
      p.join(
        p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
        'material_fonts',
        'MaterialIcons-Regular.otf',
      ),
    );
    if (iconFont.existsSync())
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
          ))
          .load();
    tester.view.physicalSize = const Size(1180, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory('build/audit/workflow-fixtures')
      ..createSync(recursive: true);
    final pdfPath = p.absolute('${root.path}/Project notes.pdf');
    final imagePath = p.absolute('${root.path}/Colour sample.png');
    await tester.runAsync(() async {
      final document = pw.Document();
      for (var i = 1; i <= 3; i++) {
        document.addPage(
          pw.Page(
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PROJECT NOTES',
                  style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 26),
                pw.Text(
                  [
                    'A simpler workflow',
                    'All on your device',
                    'Ready when you are',
                  ][i - 1],
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Container(height: 5, width: 70, color: PdfColors.orange400),
                pw.SizedBox(height: 28),
                pw.Text(
                  'Review the files. Make your changes. Save them with a name that makes sense.',
                  style: const pw.TextStyle(fontSize: 14, lineSpacing: 6),
                ),
                pw.SizedBox(height: 35),
                pw.Container(
                  width: 440,
                  height: 160,
                  padding: const pw.EdgeInsets.all(24),
                  color: PdfColors.grey100,
                  child: pw.Text(
                    'Page $i\n\nA local preview of your original document.',
                    style: const pw.TextStyle(fontSize: 18),
                  ),
                ),
                pw.Spacer(),
                pw.Text('$i / 3', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
      }
      await File(pdfPath).writeAsBytes(await document.save());
      final image = img.Image(width: 960, height: 600);
      img.fill(image, color: img.ColorRgb8(230, 192, 126));
      img.fillRect(
        image,
        x1: 70,
        y1: 70,
        x2: 500,
        y2: 480,
        color: img.ColorRgb8(51, 100, 93),
      );
      img.fillCircle(
        image,
        x: 610,
        y: 270,
        radius: 190,
        color: img.ColorRgb8(211, 101, 67),
      );
      img.fillRect(
        image,
        x1: 690,
        y1: 330,
        x2: 890,
        y2: 530,
        color: img.ColorRgb8(246, 239, 223),
      );
      await File(imagePath).writeAsBytes(img.encodePng(image));
    });
    final boundary = GlobalKey();
    Future<void> settle([int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<void> save(String name) async {
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/audit/gui-renders')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> scene(String title, List<String> files) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ConvertoApp(key: UniqueKey()),
        ),
      );
      await settle(3);
      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      final drop = tester.widget<DropTarget>(find.byType(DropTarget));
      await tester.runAsync(() async {
        for (var repeat = 0; repeat < 3; repeat++) {
          drop.onDragDone!(
            DropDoneDetails(
              files: files.map(XFile.new).toList(),
              localPosition: Offset.zero,
              globalPosition: Offset.zero,
            ),
          );
        }
      });
      await settle();
      expect(
        tester.widget<WorkspaceFileList>(find.byType(WorkspaceFileList)).paths,
        files,
      );
    }

    await scene('Merge PDF', [pdfPath, imagePath]);
    await tester.enterText(
      find.descendant(
        of: find.byType(OutputNameField),
        matching: find.byType(TextField),
      ),
      'Combined project notes',
    );
    await tester.pumpAndSettle();
    await save('merge-preview');
    // The same actual job worker used by the app, with explicit Run.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('run-tool')));
    });
    await settle(25);
    expect(find.text('1 file ready'), findsOneWidget);
    await save('saved-results');
    await tester.tap(find.byTooltip('Preview result'));
    await settle(8);
    await save('result-preview');
    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();
    await scene('Organize pages', [pdfPath]);
    await tester.ensureVisible(find.text('Arrange pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Duplicate page 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rotate page 2'));
    await settle(3);
    await save('organize-pages');
    await scene('Image editor', [imagePath]);
    await settle(8);
    await save('image-edit-preview');
    await scene('Crop PDF', [pdfPath]);
    await save('crop-preview');
    tester.view.physicalSize = const Size(780, 600);
    await tester.pumpAndSettle();
    await save('crop-compact');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
