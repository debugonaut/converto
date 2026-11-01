import 'package:path/path.dart' as p;

/// Names are file basenames, never destinations. Extensions follow the encoder.
class OutputNames {
  static String? error(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter an output name.';
    if (name == '.' || name == '..' || name.endsWith('.')) {
      return 'Use a name that does not end with a dot.';
    }
    if (RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]').hasMatch(name)) {
      return 'Use a filename without slashes or < > : " | ? *.';
    }
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
      caseSensitive: false,
    ).hasMatch(name.split('.').first)) {
      return 'This filename is reserved by the operating system.';
    }
    return null;
  }

  static String? fieldError(String value, String extension) {
    try {
      base(value, extension: extension);
      return null;
    } on ArgumentError catch (problem) {
      return problem.message.toString();
    }
  }

  static String base(String value, {String? extension}) {
    final problem = error(value);
    if (problem != null) throw ArgumentError(problem);
    var name = value.trim();
    if (extension != null) {
      final supplied = p
          .extension(name)
          .substring(p.extension(name).isEmpty ? 0 : 1)
          .toLowerCase();
      if (supplied == extension ||
          ({'jpg', 'jpeg'}.contains(supplied) &&
              {'jpg', 'jpeg'}.contains(extension))) {
        name = p.basenameWithoutExtension(name);
      }
    }
    final problemAfterExtension = error(name);
    if (problemAfterExtension != null)
      throw ArgumentError(problemAfterExtension);
    return name;
  }

  static String filename(
    String value,
    String extension, {
    int? index,
    int total = 1,
  }) {
    final stem = base(value, extension: extension);
    final digits = total.toString().length < 3 ? 3 : total.toString().length;
    return '$stem${index == null ? '' : '_${index.toString().padLeft(digits, '0')}'}.$extension';
  }
}
