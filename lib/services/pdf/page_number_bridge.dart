// pdf_manipulator 5.0.1 emits flat corner/margin fields, while its pinned
// pdf_oxide 0.3.78 bridge reads a posFields float list. Keep this compatibility
// adapter isolated and remove it when an upstream release fixes the protocol.
// ignore_for_file: implementation_imports
import 'dart:typed_data';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/src/bridge/pdf_bridge.dart';
import 'package:pdf_manipulator/src/bridge/pdf_transport.dart';
import 'package:pdf_manipulator/src/bridge/shared_bridge.dart';
import 'package:pdf_manipulator/src/bridge/protocol/binary_codec.dart' as wire;
import 'package:pdf_manipulator/src/runtime/host.dart';
import 'package:pdf_manipulator/src/runtime/router.dart';
import 'package:pdf_manipulator/src/runtime/wire_peek.dart';
import 'package:pdf_manipulator/src/types/cancel_hook.dart';

Future<T> withPageNumberEditor<T>(
  DataSource source,
  Future<T> Function(BridgeEditorHandle editor) action, {
  List<double> Function()? positionFields,
}) async {
  final host = createLaneHost();
  final bridge = SharedBridge(
    _CornerTransport(
      Router(host: host, maxLanes: 1, mode: host.mode),
      positionFields,
    ),
  );
  try {
    final editor = await bridge.openEditor(source);
    try {
      return await action(editor);
    } finally {
      await editor.dispose();
    }
  } finally {
    await bridge.dispose();
  }
}

class _CornerTransport implements PdfTransport {
  _CornerTransport(this.delegate, this.positionFields);
  final PdfTransport delegate;
  final List<double> Function()? positionFields;

  @override
  Future<({Uint8List bytes, Map<int, int> resourceIds})> execute(
    Uint8List request, {
    List<DataSource> sources = const [],
    List<DataSink> sinks = const [],
    Set<int> keepSources = const {},
    CancelHook? cancel,
  }) {
    // This private editor performs only watermark mutations; all other calls
    // (open/save/dispose) pass through unchanged, retaining streaming I/O.
    if (peekRequestOp(request) == 'editorMutate') {
      final field = wire.encodeRequest('', {
        'posFields': positionFields?.call() ?? <double>[3, 24, 20],
      });
      final corrected = Uint8List(request.length + field.length - 3)
        ..setRange(0, request.length, request)
        ..setRange(
          request.length,
          request.length + field.length - 3,
          field.sublist(3),
        );
      final header = ByteData.sublistView(corrected);
      final countOffset = 1 + request[0];
      header.setUint16(
        countOffset,
        header.getUint16(countOffset, Endian.little) + 1,
        Endian.little,
      );
      request = corrected;
    }
    return delegate.execute(
      request,
      sources: sources,
      sinks: sinks,
      keepSources: keepSources,
      cancel: cancel,
    );
  }

  @override
  Future<void> releaseSource(int resourceId) =>
      delegate.releaseSource(resourceId);
  @override
  Future<List<Uint8List>> installPrelude(
    Uint8List request, {
    required Uint8List sourceBytes,
  }) => delegate.installPrelude(request, sourceBytes: sourceBytes);
  @override
  PdfIoMode? get ioMode => delegate.ioMode;
  @override
  Future<PdfIoMode> ensureInitialized() => delegate.ensureInitialized();
  @override
  Future<void> dispose() => delegate.dispose();
}
