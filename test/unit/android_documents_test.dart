import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/services/app_paths.dart';
import 'package:converto/services/gui/android_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(AndroidDocuments.channel, null),
  );

  test(
    'Android paths are private and desktop environment overrides still win',
    () async {
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        expect(call.method, 'storagePaths');
        return {'data': '/private/app/data', 'output': '/private/app/results'};
      });
      await AndroidDocuments.initialize();
      expect(AppPaths.dataDirectory({}), '/private/app/data');
      expect(AppPaths.mobileOutputDirectory, '/private/app/results');
      expect(
        AppPaths.dataDirectory({'CONVERTO_DATA_DIR': '/override'}),
        '/override',
      );
      expect(
        () => AppPaths.configureMobile(data: '.', output: '/results'),
        throwsArgumentError,
      );
    },
  );

  test(
    'document cancellation is distinct from an empty file selection or failure',
    () async {
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        if (call.method == 'pickFiles') return null;
        expect(call.method, 'exportFile');
        expect(call.arguments, {
          'path': '/private/results/name with spaces.pdf',
        });
        return false;
      });
      expect(await AndroidDocuments.pickFiles(), isNull);
      expect(
        await AndroidDocuments.exportFile(
          '/private/results/name with spaces.pdf',
        ),
        isFalse,
      );
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        throw PlatformException(
          code: 'DOCUMENT_ERROR',
          message: 'Provider unavailable',
        );
      });
      await expectLater(
        AndroidDocuments.exportFile('/result.pdf'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'import preserves concrete paths and complete file extensions',
    () async {
      const paths = [
        '/cache/import/0/report.final.docx',
        '/cache/import/1/photo one.png',
      ];
      messenger.setMockMethodCallHandler(
        AndroidDocuments.channel,
        (call) async => paths,
      );
      expect(await AndroidDocuments.pickFiles(), paths);
    },
  );
}
