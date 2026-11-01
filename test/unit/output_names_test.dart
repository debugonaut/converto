import 'package:flutter_test/flutter_test.dart';
import 'package:converto/services/gui/output_names.dart';

void main() {
  test(
    'names keep spaces, Unicode and version dots while fixing the extension',
    () {
      expect(
        OutputNames.filename('  Résumé 日本語 v2  ', 'pdf'),
        'Résumé 日本語 v2.pdf',
      );
      expect(OutputNames.filename('Report.PDF', 'pdf'), 'Report.pdf');
      expect(OutputNames.filename('photo.jpeg', 'jpg'), 'photo.jpg');
      expect(OutputNames.filename('report.v2', 'pdf'), 'report.v2.pdf');
      expect(OutputNames.fieldError('report..pdf', 'pdf'), isNotNull);
      expect(OutputNames.fieldError('Report.PDF', 'pdf'), isNull);
    },
  );
  test(
    'rejects path traversal, control characters and portable device names',
    () {
      for (final name in [
        '',
        ' ',
        '.',
        '..',
        '../escape',
        r'..\escape',
        '/tmp/out',
        'C:drive',
        'a\nb',
        'a\u0000b',
        'CON',
        'nul.txt',
        'LPT1',
        'COM9.pdf',
        'file.',
        'a*b',
        'a?b',
        'a|b',
      ]) {
        expect(OutputNames.error(name), isNotNull, reason: name);
        expect(
          () => OutputNames.filename(name, 'pdf'),
          throwsArgumentError,
          reason: name,
        );
      }
    },
  );
  test(
    'multi-output numbering grows without truncation or output count limits',
    () {
      expect(
        OutputNames.filename('scan', 'png', index: 1, total: 3),
        'scan_001.png',
      );
      expect(
        OutputNames.filename('scan', 'png', index: 10000, total: 10000),
        'scan_10000.png',
      );
    },
  );
}
