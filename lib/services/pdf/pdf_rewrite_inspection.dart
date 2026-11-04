import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

typedef _Reference = ({int object, int generation});
typedef _Dictionary = Map<String, Object>;
typedef _PdfObject = ({Object value, bool stream});

/// Inspects object headers in the pinned engine's classic full rewrite.
/// Xref offsets let us skip image, attachment and page-content stream bytes.
class PdfRewriteInspection {
  PdfRewriteInspection._(this._objects);
  final Map<_Reference, _PdfObject> _objects;
  static const _maxHeader = 4 * 1024 * 1024;

  static Future<PdfRewriteInspection> read(File file) async {
    final input = await file.open();
    try {
      final length = await input.length();
      final tailStart = math.max(0, length - 1024);
      await input.setPosition(tailStart);
      final tail = latin1.decode(await input.read(length - tailStart));
      final marker = RegExp(r'startxref\s+(\d+)\s+%%EOF\s*$').firstMatch(tail);
      if (marker == null) _unverifiable();
      final xref = int.parse(marker[1]!);
      if (xref >= tailStart + marker.start ||
          length - xref > 32 * 1024 * 1024) {
        _unverifiable();
      }
      await input.setPosition(xref);
      final table = latin1.decode(await input.read(length - xref));
      final section = RegExp(r'^xref\r?\n(\d+) (\d+)\r?\n').firstMatch(table);
      if (section == null) _unverifiable();

      final first = int.parse(section[1]!);
      final count = int.parse(section[2]!);
      final locations = <(_Reference, int)>[];
      final row = RegExp(r'(\d{10}) (\d{5}) ([nf])[ \t]*\r?\n');
      var cursor = section.end;
      for (var index = 0; index < count; index++) {
        final entry = row.matchAsPrefix(table, cursor);
        if (entry == null) _unverifiable();
        cursor = entry.end;
        if (entry[3] == 'n') {
          locations.add((
            (object: first + index, generation: int.parse(entry[2]!)),
            int.parse(entry[1]!),
          ));
        }
      }
      if (!table.startsWith('trailer', cursor) || locations.isEmpty) {
        _unverifiable();
      }
      locations.sort((left, right) => left.$2.compareTo(right.$2));

      final objects = <_Reference, _PdfObject>{};
      for (var index = 0; index < locations.length; index++) {
        final (reference, offset) = locations[index];
        final end = index + 1 < locations.length
            ? locations[index + 1].$2
            : xref;
        if (offset < 0 || offset >= end || end > xref) _unverifiable();
        final limit = math.min(end - offset, _maxHeader);
        var size = math.min(limit, 4096);
        while (true) {
          await input.setPosition(offset);
          final header = latin1.decode(await input.read(size));
          try {
            final parser = _ObjectParser(header);
            if (parser.take() != '${reference.object}' ||
                parser.take() != '${reference.generation}' ||
                parser.take() != 'obj') {
              _unverifiable();
            }
            final value = parser.value();
            final terminator = parser.take();
            if (terminator != 'stream' && terminator != 'endobj') {
              _unverifiable();
            }
            objects[reference] = (value: value, stream: terminator == 'stream');
            break;
          } on _IncompleteHeader {
            if (size == limit) _unverifiable();
            size = math.min(size * 2, limit);
          }
        }
      }
      return PdfRewriteInspection._(objects);
    } finally {
      await input.close();
    }
  }

  bool containsAnyName(Set<String> names) {
    bool contains(Object value) => switch (value) {
      _Dictionary map =>
        map.keys.any(names.contains) || map.values.any(contains),
      List<Object> list => list.any(contains),
      String name => names.contains(name),
      _ => false,
    };
    return _objects.values.any((object) => contains(object.value));
  }

  Iterable<_Dictionary> get annotations sync* {
    for (final object in _objects.values) {
      final page = object.value;
      if (page is! _Dictionary || !page.containsKey('/Annots')) continue;
      final array = _resolve(page['/Annots']);
      if (array == 'null') continue;
      if (array is! List<Object>) _unverifiable();
      for (final item in array) {
        final annotation = _resolve(item);
        if (annotation is! _Dictionary) _unverifiable();
        yield annotation;
      }
    }
  }

  bool hasNormalAppearance(_Dictionary annotation) {
    final appearance = _resolve(annotation['/AP']);
    if (appearance is! _Dictionary) return false;
    final normal = appearance['/N'];
    final stream = normal is _Reference ? _objects[normal] : null;
    final form = stream?.value;
    return (stream?.stream ?? false) &&
        form is _Dictionary &&
        _hasRectangle(form['/BBox']) &&
        _hasRectangle(annotation['/Rect']);
  }

  bool _hasRectangle(Object? value) =>
      value is List<Object> &&
      value.length == 4 &&
      value.every(
        (coordinate) =>
            coordinate is String &&
            (double.tryParse(coordinate)?.isFinite ?? false),
      );

  Object? _resolve(Object? value) =>
      value is _Reference ? _objects[value]?.value : value;
}

Never _unverifiable() => throw ArgumentError(
  'This PDF could not be checked safely. No output was saved.',
);

class _IncompleteHeader implements Exception {
  const _IncompleteHeader();
}

class _ObjectParser {
  _ObjectParser(this.text);

  final String text;
  int _cursor = 0;
  static final _whitespace = RegExp(r'[\x00\t\n\f\r ]+|%[^\r\n]*[\r\n]');
  static final _token = RegExp(
    r'<<|>>|\[|\]|/[^\x00\t\n\f\r ()<>\[\]{}/%]*|[^\x00\t\n\f\r ()<>\[\]{}/%]+',
  );
  static final _number = RegExp(r'^[0-9]+$');
  static final _escape = RegExp(r'#([0-9a-fA-F]{2})');

  String take() {
    while (true) {
      final whitespace = _whitespace.matchAsPrefix(text, _cursor);
      if (whitespace == null) break;
      _cursor = whitespace.end;
    }
    if (_cursor == text.length) throw const _IncompleteHeader();
    if (text[_cursor] == '(') {
      var nesting = 1;
      while (++_cursor < text.length) {
        final char = text[_cursor];
        if (char == r'\') {
          _cursor++;
        } else if (char == '(') {
          nesting++;
        } else if (char == ')' && --nesting == 0) {
          _cursor++;
          return '(string)';
        }
      }
      throw const _IncompleteHeader();
    }
    if (text[_cursor] == '<' && !text.startsWith('<<', _cursor)) {
      final end = text.indexOf('>', _cursor + 1);
      if (end < 0) throw const _IncompleteHeader();
      _cursor = end + 1;
      return '(string)';
    }
    final match = _token.matchAsPrefix(text, _cursor);
    if (match == null || match.end == text.length) {
      throw const _IncompleteHeader();
    }
    _cursor = match.end;
    final token = match[0]!;
    return token.startsWith('/')
        ? token.replaceAllMapped(
            _escape,
            (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
          )
        : token;
  }

  Object value([int depth = 0, String? first]) {
    if (depth > 128) _unverifiable();
    final token = first ?? take();
    if (token == '<<') {
      final map = <String, Object>{};
      for (var key = take(); key != '>>'; key = take()) {
        if (!key.startsWith('/') || map.containsKey(key)) _unverifiable();
        map[key] = value(depth + 1);
      }
      return map;
    }
    if (token == '[') {
      final list = <Object>[];
      for (var item = take(); item != ']'; item = take()) {
        list.add(value(depth + 1, item));
      }
      return list;
    }
    if (_number.hasMatch(token)) {
      final saved = _cursor;
      final generation = take();
      if (_number.hasMatch(generation) && take() == 'R') {
        return (object: int.parse(token), generation: int.parse(generation));
      }
      _cursor = saved;
    }
    if (token == '>>' || token == ']') _unverifiable();
    return token;
  }
}
