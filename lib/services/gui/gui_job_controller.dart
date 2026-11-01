import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../../core/utils/file_utils.dart';
import '../history_service.dart';
import '../pdf/pdf_engine.dart';
import 'gui_executor.dart';

class GuiJobController extends ChangeNotifier {
  bool busy = false;
  bool cancelling = false;
  double progress = 0;
  String message = '';
  String? error;
  GuiResult? result;
  SendPort? _cancelPort;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void reset() {
    if (busy) return;
    result = null;
    error = null;
    message = '';
    progress = 0;
    _changed();
  }

  Future<void> run(GuiRequest request, {bool remember = true}) async {
    if (busy) return;
    busy = true;
    cancelling = false;
    error = null;
    result = null;
    progress = 0;
    message = 'Starting…';
    _changed();
    final receive = ReceivePort();
    final done = Completer<void>();
    final subscription = receive.listen((event) {
      if (event is SendPort) {
        _cancelPort = event;
        if (cancelling) _cancelPort!.send(true);
      } else if (event is Map) {
        switch (event['type']) {
          case 'progress':
            progress = event['value'] as double;
            if (!cancelling) message = event['message'] as String;
            _changed();
          case 'done':
            result = GuiResult(
              List<String>.from(event['outputs'] as List),
              List<String>.from(event['details'] as List),
              Map<String, String>.from(event['sources'] as Map),
            );
            message = 'Complete';
            if (!done.isCompleted) done.complete();
          case 'cancelled':
            message = 'Cancelled. No output files were saved.';
            if (!done.isCompleted) done.complete();
          case 'error':
            error = event['message'] as String;
            message = 'Could not complete this operation.';
            if (!done.isCompleted) done.complete();
        }
      } else if (!done.isCompleted) {
        error = 'The local worker stopped unexpectedly. Please try again.';
        done.complete();
      }
    });
    try {
      await Isolate.spawn(
        _worker,
        (receive.sendPort, request),
        onError: receive.sendPort,
        onExit: receive.sendPort,
        errorsAreFatal: true,
      );
      await done.future;
      if (remember && result != null && result!.outputs.isNotEmpty) {
        final records = <HistoryItem>[];
        final outputs = result!.outputs;
        final recentOutputs = outputs.length > 1000
            ? outputs.skip(outputs.length - 1000)
            : outputs;
        for (final output in recentOutputs) {
          final source = result!.sourcePaths[output] ?? request.paths.first;
          records.add(
            HistoryItem(
              id: '${DateTime.now().microsecondsSinceEpoch}-$output',
              sourceName: FileUtils.getFileName(source),
              sourcePath: source,
              sourceFormat: FileUtils.getExtension(source),
              targetPath: output,
              targetFormat: FileUtils.getExtension(output),
              fileSizeBytes: await File(output).length(),
              timestamp: DateTime.now(),
            ),
          );
        }
        await HistoryService().addRecords(records);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      await subscription.cancel();
      receive.close();
      _cancelPort = null;
      busy = false;
      cancelling = false;
      _changed();
    }
  }

  void cancel() {
    if (!busy || cancelling) return;
    cancelling = true;
    message = 'Stopping after the current operation finishes…';
    _cancelPort?.send(true);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

Future<void> _worker((SendPort, GuiRequest) input) async {
  final (port, request) = input;
  final cancellation = ReceivePort();
  var cancelled = false;
  cancellation.listen((_) => cancelled = true);
  port.send(cancellation.sendPort);
  try {
    final result = await GuiExecutor.run(
      request,
      isCancelled: () => cancelled,
      onProgress: (value, message) =>
          port.send({'type': 'progress', 'value': value, 'message': message}),
    );
    port.send({
      'type': 'done',
      'outputs': result.outputs,
      'details': result.details,
      'sources': result.sourcePaths,
    });
  } on GuiCancelled {
    port.send({'type': 'cancelled'});
  } catch (e) {
    port.send({'type': 'error', 'message': PdfEngine.errorMessage(e)});
  } finally {
    await PdfEngine.dispose();
    cancellation.close();
  }
}
