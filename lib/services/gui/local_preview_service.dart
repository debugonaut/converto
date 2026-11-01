import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show Endian;
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:xml/xml.dart';
import '../../core/constants/format_types.dart';
import '../../core/utils/file_utils.dart';
import '../../models/gui/file_preview.dart';

/// One local worker, deduplicated requests and a bounded memory-only LRU.
/// Rendering is requested by visible widgets, never by a build-loop or watcher.
class LocalPreviewService {
  static const channel = MethodChannel('converto/local_preview');
  final Future<FilePreview> Function(
    String path,
    int page,
    int dimension,
    String? password,
  )?
  renderer;
  final int maxEntries;
  final int maxMemoryBytes;
  final _cache = LinkedHashMap<String, FilePreview>();
  final _inflight = <String, Future<FilePreview>>{};
  final _requests = <int, Completer<Map>>{};
  Completer<SendPort?>? _ready;
  SendPort? _port;
  int _nextId = 0;
  int _memory = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _paused = false;
  Completer<void>? _resume;
  Future<void> _tail = Future.value();
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (value) {
      _resume = Completer<void>();
    } else {
      _resume?.complete();
      _resume = null;
    }
  }

  LocalPreviewService({
    this.renderer,
    this.maxEntries = 24,
    this.maxMemoryBytes = 16 * 1024 * 1024,
  });

  int get cacheEntries => _cache.length;
  int get cachedBytes => _memory;

  Future<FilePreview> load(
    String path, {
    int page = 0,
    int dimension = 800,
    String? password,
  }) async {
    if (_disposed) return FilePreview(path: path, message: 'Preview closed.');
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file)
        return FilePreview(
          path: path,
          kind: 'error',
          message: 'File moved or deleted.',
        );
      if (_disposed) return FilePreview(path: path, message: 'Preview closed.');
      final size = dimension.clamp(80, 1600);
      final key =
          '$path|${stat.modified.microsecondsSinceEpoch}|${stat.size}|$page|$size';
      // Passwords and decrypted previews are never placed in the shared cache.
      if (password == null) {
        final cached = _cache.remove(key);
        if (cached != null) {
          _cache[key] = cached;
          return cached;
        }
        final pending = _inflight[key];
        if (pending != null) return await pending;
      }
      final generation = _generation;
      final future = _queue(path, page, size, password);
      if (password == null) _inflight[key] = future;
      try {
        final result = await future;
        if (!_disposed &&
            generation == _generation &&
            password == null &&
            result.memoryBytes <= maxMemoryBytes) {
          _cache[key] = result;
          _memory += result.memoryBytes;
          while (_cache.length > maxEntries || _memory > maxMemoryBytes) {
            _memory -= _cache.remove(_cache.keys.first)!.memoryBytes;
          }
        }
        return result;
      } finally {
        if (password == null && identical(_inflight[key], future))
          _inflight.remove(key);
      }
    } on FileSystemException {
      return FilePreview(
        path: path,
        kind: 'error',
        message: 'Cannot read this file. Check its permissions.',
      );
    } catch (_) {
      return FilePreview(
        path: path,
        kind: 'error',
        message: 'Local preview is unavailable. Open the original file.',
      );
    }
  }

  Future<FilePreview> _queue(
    String path,
    int page,
    int dimension,
    String? password,
  ) {
    final result = Completer<FilePreview>();
    _tail = _tail.then((_) async {
      while (_paused && !_disposed) {
        await _resume?.future;
      }
      if (_disposed) {
        result.complete(FilePreview(path: path, message: 'Preview closed.'));
        return;
      }
      try {
        result.complete(await _load(path, page, dimension, password));
      } catch (_) {
        result.complete(
          FilePreview(
            path: path,
            kind: 'error',
            message: 'Preview unavailable. Open original to inspect.',
          ),
        );
      }
    });
    return result.future;
  }

  Future<FilePreview> _load(
    String path,
    int page,
    int dimension,
    String? password,
  ) async {
    if (renderer != null) return renderer!(path, page, dimension, password);
    final category = FormatRegistry.getFormatInfo(
      FileUtils.getExtension(path),
    ).category;
    if (Platform.isMacOS &&
        [
          FileCategory.image,
          FileCategory.document,
          FileCategory.spreadsheet,
          FileCategory.presentation,
        ].contains(category) &&
        !['txt', 'csv'].contains(FileUtils.getExtension(path))) {
      try {
        final data = await channel.invokeMapMethod<String, dynamic>(
          category == FileCategory.image ? 'thumbnail' : 'documentThumbnail',
          {'path': path, 'page': page, 'dimension': dimension},
        );
        if (data != null) return FilePreview.fromMap(data);
      } on MissingPluginException {
        /* Dart fallback for tests and other hosts. */
      } on PlatformException {
        /* A native codec can reject a supported Dart image. */
      }
    }
    final data = await _request({
      'path': path,
      'page': page,
      'dimension': dimension,
      if (password != null) 'password': password,
    });
    if (data['path'] == '') data['path'] = path;
    final image = data['image'];
    if (image is TransferableTypedData)
      data['image'] = image.materialize().asUint8List();
    return FilePreview.fromMap(data);
  }

  Future<Map> _request(Map<String, Object> data) async {
    if (_disposed) return {'path': data['path'], 'message': 'Preview closed.'};
    if (_ready == null) {
      final ready = Completer<SendPort?>();
      _ready = ready;
      final receive = ReceivePort();
      receive.listen((message) {
        if (message is SendPort) {
          _port = message;
          if (!ready.isCompleted) ready.complete(message);
          if (_disposed) message.send(null);
        } else if (message is Map && message['id'] is int) {
          _requests.remove(message['id'])?.complete(message['data'] as Map);
        } else {
          if (!ready.isCompleted) ready.complete(null);
          for (final entry in _requests.values) {
            if (!entry.isCompleted)
              entry.complete({
                'path': '',
                'kind': 'error',
                'message':
                    'Local preview worker stopped. Reopen the file to retry.',
              });
          }
          _requests.clear();
          if (identical(_ready, ready)) {
            _ready = null;
            _port = null;
          }
          receive.close();
        }
      });
      unawaited(
        Isolate.spawn(
          _previewWorker,
          receive.sendPort,
          onError: receive.sendPort,
          onExit: receive.sendPort,
        ).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!ready.isCompleted) ready.complete(null);
            if (identical(_ready, ready)) _ready = null;
            receive.close();
          },
        ),
      );
    }
    final port = await _ready!.future;
    if (_disposed || port == null)
      return {
        'path': data['path'],
        'kind': 'error',
        'message': 'Preview is unavailable. Open the original file.',
      };
    final id = _nextId++;
    final complete = Completer<Map>();
    _requests[id] = complete;
    port.send({'id': id, ...data});
    return complete.future;
  }

  void clear() {
    _generation++;
    _cache.clear();
    _inflight.clear();
    _memory = 0;
  }

  void dispose() {
    _disposed = true;
    paused = false;
    clear();
    _port?.send(null);
    // The worker finishes its current native call and disposes its PDF context.
  }
}

Future<void> _previewWorker(SendPort parent) async {
  final receive = ReceivePort();
  parent.send(receive.sendPort);
  Pdf? pdf;
  try {
    await for (final request in receive) {
      if (request == null) break;
      final data = Map<String, dynamic>.from(request as Map);
      final path = data['path'] as String;
      final result = <String, Object?>{
        'path': path,
        'page': data['page'],
        'sizeBytes': 0,
      };
      try {
        final source = File(path);
        result['sizeBytes'] = await source.length();
        final extension = FileUtils.getExtension(path);
        final category = FormatRegistry.getFormatInfo(extension).category;
        final dimension = data['dimension'] as int;
        final page = data['page'] as int;
        if (category == FileCategory.pdf) {
          pdf ??= Pdf();
          final document = await pdf.open(
            FileSource(source),
            password: data['password'] as String?,
          );
          try {
            if (page < 0 || page >= document.pageCount)
              throw ArgumentError('Page is outside this PDF.');
            final info = document.pages[page];
            result.addAll({
              'kind': 'pdf',
              'pageCount': document.pageCount,
              'width': info.effectiveWidth,
              'height': info.effectiveHeight,
              'encrypted': document.isEncrypted,
            });
            await for (final rendered in document.render(
              pages: PdfPages.single(page),
              size: PdfRenderSize.thumbnail(dimension),
            )) {
              final png = img.PngDecoder().startDecode(rendered.data);
              result.addAll({
                'image': TransferableTypedData.fromList([rendered.data]),
                'rasterWidth': png?.width ?? dimension,
                'rasterHeight': png?.height ?? dimension,
              });
              break;
            }
          } finally {
            await document.dispose();
          }
        } else if (category == FileCategory.image) {
          // Mac uses ImageIO thumbnails directly from disk; this fallback is
          // bounded for automatic previews, never a conversion/file-size cap.
          if (await source.length() > 32 * 1024 * 1024) {
            result['message'] =
                'Open original to inspect this large image. Processing remains available.';
          } else {
            final bytes = await source.readAsBytes();
            final decoder = img.findDecoderForData(bytes);
            final info = decoder?.startDecode(bytes);
            if (info == null)
              throw const FormatException('Unrecognized image data.');
            if (info.width * info.height > 50000000) {
              result.addAll({
                'width': info.width,
                'height': info.height,
                'message':
                    'Open original for a full-size preview. Processing remains available.',
              });
            } else {
              var frame = page;
              var count = info.numFrames;
              if (extension == 'ico') {
                frame = 0;
                count = 1;
                if (info is img.IcoInfo) {
                  var area = 0;
                  for (var i = 0; i < info.images.length; i++) {
                    final item = info.images[i];
                    if (item.width * item.height > area) {
                      area = item.width * item.height;
                      frame = i;
                    }
                  }
                }
              }
              var image = decoder!.decodeFrame(frame);
              if (image == null)
                throw const FormatException('Cannot decode image frame.');
              image = img.bakeOrientation(image);
              final width = image.width, height = image.height;
              if (width > dimension || height > dimension) {
                image = img.copyResize(
                  image,
                  width: width >= height ? dimension : null,
                  height: height > width ? dimension : null,
                );
              }
              result.addAll({
                'kind': 'image',
                'pageCount': count,
                'width': width,
                'height': height,
                'rasterWidth': image.width,
                'rasterHeight': image.height,
                'image': TransferableTypedData.fromList([
                  Uint8List.fromList(img.encodePng(image)),
                ]),
              });
            }
          }
        } else if (extension == 'txt' || extension == 'csv') {
          final input = await source.open();
          late Uint8List bytes;
          try {
            bytes = await input.read(64 * 1024);
          } finally {
            await input.close();
          }
          String text;
          if (bytes.length >= 2 &&
              ((bytes[0] == 255 && bytes[1] == 254) ||
                  (bytes[0] == 254 && bytes[1] == 255))) {
            final data = ByteData.sublistView(bytes);
            final endian = bytes[0] == 255 ? Endian.little : Endian.big;
            text = String.fromCharCodes(
              List.generate(
                (bytes.length - 2) ~/ 2,
                (i) => data.getUint16(2 + 2 * i, endian),
              ),
            );
          } else {
            text = utf8.decode(bytes, allowMalformed: true);
          }
          result.addAll({
            'kind': 'text',
            'text': text.length > 6000 ? '${text.substring(0, 6000)}\n…' : text,
          });
        } else if (['docx', 'xlsx', 'pptx', 'odt'].contains(extension)) {
          final stream = InputFileStream(path);
          try {
            final archive = ZipDirectory.read(stream);
            String xml(String name) {
              final entry = archive.fileHeaders
                  .where((item) => item.filename == name)
                  .firstOrNull;
              final file = entry?.file;
              if (file == null ||
                  (entry?.uncompressedSize ?? 0) > _ExcerptOutput.limit ||
                  file.flags & 1 != 0)
                return '';
              final raw = file.rawContent;
              if (raw == null) return '';
              final output = _ExcerptOutput();
              // Stream the requested member only. ArchiveFile.decompress is a
              // no-op for ZipDecoder's FileContent wrapper in archive 3.6.
              if (file.compressionMethod == ZipFile.zipCompressionDeflate) {
                Inflate.stream(raw, output);
              } else if (file.compressionMethod ==
                  ZipFile.zipCompressionStore) {
                output.writeInputStream(raw);
              } else {
                return '';
              }
              final bytes = output.getBytes();
              return utf8.decode(bytes, allowMalformed: true);
            }

            String content = '';
            if (extension == 'docx' || extension == 'odt') {
              final text = xml(
                extension == 'docx' ? 'word/document.xml' : 'content.xml',
              );
              if (text.isNotEmpty) {
                final document = XmlDocument.parse(text);
                content = document.descendants
                    .whereType<XmlElement>()
                    .where((node) => ['p', 'h'].contains(node.name.local))
                    .take(70)
                    .map((node) => node.innerText)
                    .join('\n');
              }
            } else if (extension == 'pptx') {
              final slides =
                  archive.fileHeaders
                      .where(
                        (f) => RegExp(
                          r'^ppt/slides/slide\d+\.xml$',
                        ).hasMatch(f.filename),
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          int.parse(
                            RegExp(r'slide(\d+)').firstMatch(a.filename)![1]!,
                          ).compareTo(
                            int.parse(
                              RegExp(r'slide(\d+)').firstMatch(b.filename)![1]!,
                            ),
                          ),
                    );
              if (page < 0 || page >= slides.length)
                throw ArgumentError('Slide is outside this file.');
              result['pageCount'] = slides.length;
              final text = xml(slides[page].filename);
              if (text.isNotEmpty)
                content = XmlDocument.parse(text).descendants
                    .whereType<XmlElement>()
                    .where((node) => node.name.local == 't')
                    .map((node) => node.innerText)
                    .join('\n');
            } else {
              final sharedXml = xml('xl/sharedStrings.xml');
              final shared = sharedXml.isEmpty
                  ? <String>[]
                  : XmlDocument.parse(sharedXml).descendants
                        .whereType<XmlElement>()
                        .where((node) => node.name.local == 'si')
                        .map((node) => node.innerText)
                        .toList();
              final sheet = xml('xl/worksheets/sheet1.xml');
              if (sheet.isNotEmpty) {
                content = XmlDocument.parse(sheet).descendants
                    .whereType<XmlElement>()
                    .where((node) => node.name.local == 'row')
                    .take(20)
                    .map(
                      (row) => row.childElements
                          .take(16)
                          .map((cell) {
                            final value =
                                cell.childElements
                                    .where((n) => n.name.local == 'v')
                                    .firstOrNull
                                    ?.innerText ??
                                cell.innerText;
                            final index = int.tryParse(value);
                            return cell.getAttribute('t') == 's' &&
                                    index != null &&
                                    index >= 0 &&
                                    index < shared.length
                                ? shared[index]
                                : value;
                          })
                          .join('  |  '),
                    )
                    .join('\n');
              }
            }
            result.addAll({
              'kind': 'text',
              'text': content.length > 6000
                  ? '${content.substring(0, 6000)}\n…'
                  : content,
              'message':
                  'Local content excerpt. Open original for the complete layout.',
            });
          } finally {
            await stream.close();
          }
        } else {
          result['message'] =
              'Open original to preview this format in its local viewer.';
        }
      } catch (error) {
        final message = error.toString().toLowerCase();
        final encrypted =
            message.contains('password') || message.contains('encrypted');
        result.addAll({
          'kind': 'error',
          'encrypted': encrypted,
          'message': encrypted
              ? data['password'] == null
                    ? 'Password-protected PDF. Enter its password to preview.'
                    : 'Could not unlock preview. Check the password and try again.'
              : 'Preview unavailable. The file may be damaged or use an unsupported feature.',
        });
      }
      parent.send({'id': data['id'], 'data': result});
    }
  } finally {
    await pdf?.dispose();
    receive.close();
  }
}

class _ExcerptOutput extends OutputStream {
  static const limit = 1024 * 1024;
  @override
  void writeInputStream(InputStreamBase stream) {
    if (length + stream.length > limit)
      throw const FormatException('Preview excerpt is too large.');
    super.writeInputStream(stream);
  }

  @override
  void writeByte(int value) {
    if (length >= limit)
      throw const FormatException('Preview excerpt is too large.');
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    if (length + (len ?? bytes.length) > limit)
      throw const FormatException('Preview excerpt is too large.');
    super.writeBytes(bytes, len);
  }
}
