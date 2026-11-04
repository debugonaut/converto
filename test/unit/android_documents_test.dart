import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/services/app_paths.dart';
import 'package:converto/services/gui/mobile_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test('mobile document flows are enabled on Android and iOS only', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        MobileDocuments.enabled,
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
      );
    }
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(MobileDocuments.channel, null),
  );

  test(
    'mobile paths are private and desktop environment overrides still win',
    () async {
      messenger.setMockMethodCallHandler(MobileDocuments.channel, (call) async {
        expect(call.method, 'storagePaths');
        return {'data': '/private/app/data', 'output': '/private/app/results'};
      });
      await MobileDocuments.initialize();
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
      messenger.setMockMethodCallHandler(MobileDocuments.channel, (call) async {
        if (call.method == 'pickFiles') return null;
        expect(call.method, 'exportFile');
        expect(call.arguments, {
          'path': '/private/results/name with spaces.pdf',
        });
        return false;
      });
      expect(await MobileDocuments.pickFiles(), isNull);
      expect(
        await MobileDocuments.exportFile(
          '/private/results/name with spaces.pdf',
        ),
        isFalse,
      );
      messenger.setMockMethodCallHandler(MobileDocuments.channel, (call) async {
        throw PlatformException(
          code: 'DOCUMENT_ERROR',
          message: 'Provider unavailable',
        );
      });
      await expectLater(
        MobileDocuments.exportFile('/result.pdf'),
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
        MobileDocuments.channel,
        (call) async => paths,
      );
      expect(await MobileDocuments.pickFiles(), paths);
    },
  );
  test(
    'secondary selection requests one file and releases only its imported copy',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(MobileDocuments.channel, (call) async {
        calls.add(call);
        return call.method == 'pickFiles'
            ? ['/cache/imports/one/key.p12']
            : null;
      });
      expect(
        await MobileDocuments.pickFiles(
          extensions: ['p12', 'pfx'],
          allowMultiple: false,
        ),
        ['/cache/imports/one/key.p12'],
      );
      await MobileDocuments.releaseImport('/cache/imports/one/key.p12');
      expect(calls[0].arguments, {
        'extensions': ['p12', 'pfx'],
        'allowMultiple': false,
      });
      expect(calls[1].method, 'releaseImport');
      expect(calls[1].arguments, {'path': '/cache/imports/one/key.p12'});
    },
  );
}
