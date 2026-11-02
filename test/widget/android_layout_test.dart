import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:converto/main.dart';
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/app_paths.dart';
import 'package:converto/services/gui/gui_executor.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/services/gui/local_preview_service.dart';
import 'package:converto/ui/screens/tool_workspace.dart';
import 'package:converto/ui/widgets/workspace_results.dart';

void main() {
  testWidgets(
    'phone hub, settings and system Back work without desktop controls',
    (tester) async {
      final scratch = Directory.systemTemp.createTempSync('android-hub-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      AppPaths.configureMobile(
        data: '${scratch.path}/data',
        output: '${scratch.path}/results',
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ConvertoApp());
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Use CLI'), findsNothing);
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).platform,
        debugDefaultTargetPlatformOverride,
      );
      await tester.enterText(find.byType(TextField), 'watermark');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Watermark'));
      await tester.tap(find.text('Watermark'));
      await tester.pumpAndSettle();
      expect(find.text('Watermark text'), findsOneWidget);
      expect(find.text('Tap to choose files'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tools for your files.'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Choose folder'), findsNothing);
      expect(find.textContaining('Use Export'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'all workspaces fit a phone with enlarged text before running',
    (tester) async {
      final scratch = Directory.systemTemp.createTempSync('android-tools-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final pdf = File(
        'test_assets/notes.pdf',
      ).copySync('${scratch.path}/report with a long filename.pdf');
      final image = File('${scratch.path}/photo.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 12)));
      final job = GuiJobController();
      addTearDown(job.dispose);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final tool in ToolDefinition.tools) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: ToolWorkspace(
                  key: ValueKey(tool.id),
                  tool: tool,
                  paths: tool.id == ToolId.editImage
                      ? [image.path]
                      : tool.id == ToolId.merge
                      ? [pdf.path, image.path]
                      : [pdf.path],
                  job: job,
                  outputDirectory: scratch.path,
                  remember: false,
                  onBack: () {},
                  onPick: () async {},
                  onChooseOutput: () async {},
                  onPathsChanged: (_) {},
                  onOpen: (_, {bool reveal = false}) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tool.title);
        expect(find.text('Change folder'), findsNothing);
        expect(job.busy, isFalse);
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'phone results expose Export and route the selected result',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = LocalPreviewService();
      addTearDown(service.dispose);
      String? exported;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: WorkspaceResults(
                result: const GuiResult(['/private/results/report.pdf'], []),
                tool: ToolId.convert,
                previews: service,
                onOpen: (path, {bool reveal = false}) async {
                  if (reveal) exported = path;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      expect(exported, '/private/results/report.pdf');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
