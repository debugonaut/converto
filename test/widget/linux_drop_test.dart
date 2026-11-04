import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/main.dart';
import 'package:converto/services/gui/desktop_file_picker.dart';
import 'package:converto/ui/screens/tool_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux URI drops decode once, deduplicate and never auto-run', (
    tester,
  ) async {
    final scratch = Directory.systemTemp.createTempSync('linux-uri-drop-');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final names = ['日本語 %20 # & spaces.pdf', "apostrophe's.PDF"];
    final paths = [
      for (final name in names)
        (File(
          '${scratch.path}/$name',
        )..writeAsStringSync('not processed')).path,
    ];
    tester.view.physicalSize = const Size(1180, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ConvertoApp());
    await tester.pumpAndSettle();
    final payload =
        '${paths.map((p) => Uri.file(p).toString()).join('\r\n')}\r\n';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> event(String method, Object? args) async {
      await messenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    for (var i = 0; i < 5; i++) {
      await event(Platform.isLinux ? 'updated' : 'entered', [300.0, 300.0]);
      await tester.pump();
      await tester.runAsync(() async {
        await event('updated', [300.0, 300.0]);
        // GTK emits leave before data-received on Linux.
        if (Platform.isLinux) await event('exited', null);
        await event('performOperation_linux', [
          payload,
          [300.0, 300.0],
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      find.text('2 files selected · showing compatible tools'),
      findsOneWidget,
    );
    await tester.tap(find.text('Watermark'));
    await tester.pumpAndSettle();
    final workspace = tester.widget<ToolWorkspace>(find.byType(ToolWorkspace));
    expect(workspace.paths, paths);
    expect(workspace.job.busy, isFalse);
    expect(workspace.job.result, isNull);
    expect(scratch.listSync().length, 2);
    expect(tester.takeException(), isNull);
  }, skip: Platform.isWindows);

  test('GTK picker channel preserves literal paths and cancellation', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var cancel = false;
    messenger.setMockMethodCallHandler(DesktopFilePicker.channel, (call) async {
      calls.add(call);
      if (cancel) return null;
      return call.method == 'pickFiles'
          ? ["/home/person/日本語 %20 # apostrophe's.pdf", '/tmp/SECOND.PDF']
          : '/home/person/Output with spaces';
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(DesktopFilePicker.channel, null),
    );
    expect(await DesktopFilePicker.pickFiles(extensions: ['pdf']), [
      "/home/person/日本語 %20 # apostrophe's.pdf",
      '/tmp/SECOND.PDF',
    ]);
    expect(calls.first.arguments, {
      'extensions': ['pdf'],
      'allowMultiple': true,
    });
    expect(
      await DesktopFilePicker.pickDirectory(),
      '/home/person/Output with spaces',
    );
    cancel = true;
    expect(
      await DesktopFilePicker.pickFiles(
        extensions: ['pdf'],
        allowMultiple: false,
      ),
      isNull,
    );
    expect(calls.last.arguments, {
      'extensions': ['pdf'],
      'allowMultiple': false,
    });
    expect(await DesktopFilePicker.pickDirectory(), isNull);
  }, skip: !Platform.isLinux);
}
