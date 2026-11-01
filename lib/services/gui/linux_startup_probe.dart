import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import '../../models/gui/tool_definition.dart';
import '../pdf/pdf_engine.dart';
import 'desktop_file_picker.dart';
import 'gui_executor.dart';

/// Explicit packaging check only; never runs in an ordinary application launch.
Future<void> runLinuxStartupProbe() async {
  Directory? scratch;
  try {
    final files = await DesktopFilePicker.pickFiles(extensions: ['pdf']);
    final folder = await DesktopFilePicker.pickDirectory();
    if (files != null || folder != null)
      throw StateError('Picker cancellation');
    stdout.writeln('CONVERTO_LINUX_PICKERS_OK');
    scratch = await Directory.systemTemp.createTemp('converto-bundled-engine-');
    final pdf = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Text('Offline source')));
    final source = File('${scratch.path}/source 日本語.pdf');
    await source.writeAsBytes(await pdf.save());
    final result = await GuiExecutor.run(
      GuiRequest(
        tool: ToolId.watermark,
        paths: [source.path],
        outputDirectory: '${scratch.path}/results',
        outputName: 'Local result',
        options: const {'text': 'LOCAL'},
      ),
    );
    final output = File(result.outputs.single);
    if (await PdfEngine.pageCount(output) != 1 ||
        !(await PdfEngine.extractText(output)).contains('Offline source')) {
      throw StateError('Packaged PDF engine output verification');
    }
    Future<String> pixels(File pdf, String directory) async {
      final pages = await PdfEngine.renderPages(
        sourceFile: pdf,
        dpi: 24,
        maxPages: 1,
        outputDirectory: directory,
      );
      final image = img.decodePng(await pages.single.readAsBytes());
      if (image == null) throw StateError('Packaged PDF rendering');
      return base64Encode(image.getBytes());
    }

    if (await pixels(source, '${scratch.path}/before') ==
        await pixels(output, '${scratch.path}/after')) {
      throw StateError('Watermark did not change rendered pixels');
    }
    stdout.writeln('CONVERTO_LINUX_BUNDLED_ENGINE_OK');
  } catch (error) {
    stderr.writeln('CONVERTO_LINUX_PROBE_FAILED: $error');
  } finally {
    await PdfEngine.dispose();
    if (scratch != null) await scratch.delete(recursive: true);
    await DesktopFilePicker.channel.invokeMethod<void>('finishProbe');
  }
}
