import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';

void main() {
  test(
    'real isolate publishes results and busy guard prevents duplicate work',
    () async {
      final scratch = Directory.systemTemp.createTempSync('gui-worker-');
      final job = GuiJobController();
      try {
        final image = File('${scratch.path}/source.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 50, height: 30)));
        final request = GuiRequest(
          tool: ToolId.convert,
          paths: [image.path],
          outputDirectory: '${scratch.path}/out',
          options: {'format': 'pdf'},
        );
        final first = job.run(request, remember: false);
        await job.run(request, remember: false);
        await first;
        expect(job.busy, isFalse);
        expect(job.error, isNull);
        expect(job.result!.outputs.length, 1);
        expect(Directory('${scratch.path}/out').listSync().length, 1);
        expect(job.progress, 1);
      } finally {
        job.dispose();
        scratch.deleteSync(recursive: true);
      }
    },
  );
  test(
    'cancel before worker handshake cleans staging and can run again',
    () async {
      final scratch = Directory.systemTemp.createTempSync('gui-cancel-');
      final job = GuiJobController();
      try {
        final image = File('${scratch.path}/source.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 50, height: 30)));
        final request = GuiRequest(
          tool: ToolId.convert,
          paths: [image.path],
          outputDirectory: '${scratch.path}/out',
          options: {'format': 'pdf'},
        );
        final first = job.run(request, remember: false);
        job.cancel();
        await first;
        expect(job.busy, isFalse);
        expect(job.error, isNull);
        expect(job.result, isNull);
        expect(Directory('${scratch.path}/out').listSync(), isEmpty);
        await job.run(request, remember: false);
        expect(job.result!.outputs.length, 1);
      } finally {
        job.dispose();
        scratch.deleteSync(recursive: true);
      }
    },
  );
  test('batch source tracking survives output name collisions', () async {
    final scratch = Directory.systemTemp.createTempSync('gui-batch-');
    final job = GuiJobController();
    try {
      final paths = <String>[];
      for (final folder in ['a', 'b']) {
        Directory('${scratch.path}/$folder').createSync();
        final file = File('${scratch.path}/$folder/same.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 12)));
        paths.add(file.path);
      }
      await job.run(
        GuiRequest(
          tool: ToolId.convert,
          paths: paths,
          outputDirectory: '${scratch.path}/out',
          options: {'format': 'jpg'},
        ),
        remember: false,
      );
      expect(job.error, isNull);
      expect(job.result!.outputs.toSet().length, 2);
      expect(job.result!.sourcePaths.values.toSet(), paths.toSet());
      expect(Directory('${scratch.path}/out').listSync().length, 2);
    } finally {
      job.dispose();
      scratch.deleteSync(recursive: true);
    }
  });
}
