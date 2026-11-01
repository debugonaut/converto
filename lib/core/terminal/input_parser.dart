import 'dart:io';

/// Parses terminal text only. Process argv is already tokenized by the OS.
class TerminalInputParser {
  static List<String> tokenize(String input) {
    var text = input
        .trim()
        .replaceAll('\x1b[200~', '')
        .replaceAll('\x1b[201~', '');
    // Old terminal paste fragments are wrappers, never filename substrings.
    if (text.startsWith('00~') && text.endsWith('01~')) {
      text = text.substring(3, text.length - 3);
    }
    if (text.startsWith('& ') ||
        text.startsWith('&"') ||
        text.startsWith("&'")) {
      text = text.substring(1).trimLeft();
    }
    final result = <String>[];
    final token = StringBuffer();
    String? quote;
    bool windowsPath() =>
        RegExp(r'^[A-Za-z]:[\\/]|^\\\\').hasMatch(token.toString());
    void finish() {
      if (token.isNotEmpty) result.add(normalizePath(token.toString()));
      token.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quote != null) {
        if (c == quote) {
          // PowerShell single-quoted strings escape a quote by doubling it.
          if (quote == "'" &&
              windowsPath() &&
              i + 1 < text.length &&
              text[i + 1] == "'") {
            token.write("'");
            i++;
          } else {
            quote = null;
          }
        } else if (c == '\\' &&
            quote == '"' &&
            !windowsPath() &&
            i + 1 < text.length &&
            ['"', '\\', r'$', '`'].contains(text[i + 1])) {
          token.write(text[++i]);
        } else {
          token.write(c);
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '\\' &&
          !windowsPath() &&
          i + 1 < text.length &&
          RegExp(r'''[\s\\'"()\[\]{}&;#$`!*?<>|]''').hasMatch(text[i + 1]) &&
          !(token.isEmpty && text[i + 1] == '\\')) {
        token.write(text[++i]);
      } else if (RegExp(r'\s').hasMatch(c)) {
        finish();
      } else {
        token.write(c);
      }
    }
    if (quote != null && token.isNotEmpty) {
      throw const FormatException('Unclosed quote in file path.');
    }
    finish();
    return result.where((s) => s.isNotEmpty).toList(growable: false);
  }

  static String normalizePath(String raw) {
    var path = raw;
    if (path.startsWith('file://')) {
      if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(path)) {
        throw const FormatException('Invalid percent escape in file URI.');
      }
      final uri = Uri.parse(path);
      if (uri.host.isNotEmpty && uri.host != 'localhost') {
        throw const FormatException('Only local file:// URIs are supported.');
      }
      if (uri.hasQuery || uri.hasFragment) {
        throw const FormatException(
          'File URIs cannot contain a query or fragment.',
        );
      }
      final localUri = uri.host == 'localhost' ? uri.replace(host: '') : uri;
      final windows = RegExp(r'^/[A-Za-z]:/').hasMatch(uri.path);
      path = localUri.toFilePath(windows: windows);
    }
    if (path.startsWith('~/') || path.startsWith('~\\')) {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) path = '$home${path.substring(1)}';
    }
    final root = path == '/' || RegExp(r'^[A-Za-z]:[/\\]?$').hasMatch(path);
    if (!root) {
      while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\'))) {
        path = path.substring(0, path.length - 1);
      }
    }
    return path;
  }

  static String sanitizeToken(String raw) {
    // File names received in argv must not be shell-decoded a second time.
    if (File(raw).existsSync() || Directory(raw).existsSync()) return raw;
    final tokens = tokenize(raw);
    if (tokens.length > 1) {
      // A standalone unquoted path may contain spaces at a source-path prompt.
      return normalizePath(raw.trim());
    }
    return tokens.isEmpty ? '' : tokens.single;
  }
}
