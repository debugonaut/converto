// Automated Flutter renders, not native-window interaction coverage.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/main.dart';

void main() {
  testWidgets('render the implemented desktop tool hub', (tester) async {
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (font.existsSync()) {
      for (final family in ['.AppleSystemUIFont', 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
    }
    final iconFont = File(
      p.join(
        p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
        'material_fonts',
        'MaterialIcons-Regular.otf',
      ),
    );
    if (iconFont.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
          ))
          .load();
    }
    tester.view.physicalSize = const Size(1180, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const ConvertoApp()),
    );
    await tester.pumpAndSettle();
    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/audit/gui-renders')
          ..createSync(recursive: true);
        File(
          '${directory.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await save('tool-hub');
    await tester.tap(find.text('Merge PDF'));
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 8 && find.text('Loading output folder…').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
    await save('merge-workspace');
    expect(tester.takeException(), isNull);
  });
}
