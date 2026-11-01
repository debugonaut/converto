import 'dart:io';
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
        !(await PdfEngine.extractText(output)).contains('LOCAL')) {
      throw StateError('Packaged PDF engine output verification');
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
