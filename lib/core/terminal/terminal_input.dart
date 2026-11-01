import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TerminalInterrupted implements Exception {}

/// One stdin subscription shared by menus, raw editing and password prompts.
/// Async reads allow OS interrupts to run while the terminal is waiting.
class TerminalInput {
  static StreamController<List<int>>? _controller;
  static StreamSubscription<List<int>>? _stdin;
  static StreamSubscription<ProcessSignal>? _interrupt;
  static StreamIterator<List<int>>? _chunks;
  static List<int> _chunk = const [];
  static int _offset = 0;
  static final List<int> _pending = [];
  static bool _afterCr = false;

  static void _initialize() {
    if (_controller != null) return;
    final controller = _controller = StreamController<List<int>>();
    _chunks = StreamIterator(controller.stream);
    _stdin = stdin.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    if (!Platform.isWindows) {
      _interrupt = ProcessSignal.sigint.watch().listen((_) {
        if (!controller.isClosed) controller.add([3]);
      });
    }
  }

  static void pushBack(int byte) {
    if (byte >= 0) _pending.add(byte);
  }

  static Future<int> readByte() async {
    _initialize();
    while (true) {
      int byte;
      if (_pending.isNotEmpty) {
        byte = _pending.removeLast();
      } else {
        if (_offset >= _chunk.length) {
          if (!await _chunks!.moveNext()) return -1;
          _chunk = _chunks!.current;
          _offset = 0;
          if (_chunk.isEmpty) continue;
        }
        byte = _chunk[_offset++];
      }
      if (_afterCr && byte == 10) {
        _afterCr = false;
        continue;
      }
      _afterCr = byte == 13;
      return byte;
    }
  }

  static Future<String?> readLine() async {
    final bytes = <int>[];
    while (true) {
      final byte = await readByte();
      if (byte == 3) throw TerminalInterrupted();
      if (byte == -1 || byte == 4)
        return bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
      if (byte == 10 || byte == 13)
        return utf8.decode(bytes, allowMalformed: true);
      bytes.add(byte);
    }
  }

  static Future<void> dispose() async {
    await _interrupt?.cancel();
    await _stdin?.cancel();
    await _chunks?.cancel();
    await _controller?.close();
    _interrupt = null;
    _stdin = null;
    _chunks = null;
    _controller = null;
    _chunk = const [];
    _offset = 0;
    _pending.clear();
    _afterCr = false;
  }
}
