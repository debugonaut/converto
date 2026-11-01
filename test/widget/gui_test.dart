import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:converto/main.dart';
import 'package:converto/core/theme/app_theme.dart';
import 'package:converto/models/gui/tool_definition.dart';
import 'package:converto/services/gui/gui_job_controller.dart';
import 'package:converto/ui/screens/tool_workspace.dart';

void main() {
  testWidgets(
    'hub searches, filters and opens a workspace without processing',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ConvertoApp());
      await tester.pumpAndSettle();
      expect(find.text('Tools for your files.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'watermark');
      await tester.pumpAndSettle();
      expect(find.text('Merge PDF'), findsNothing);
      await tester.tap(find.text('Watermark'));
      await tester.pumpAndSettle();
      expect(find.text('Watermark text'), findsOneWidget);
      final run = tester.widget<FilledButton>(
        find.byKey(const Key('run-tool')),
      );
      expect(run.onPressed, isNull);
      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-a-tool');
      await tester.pumpAndSettle();
      expect(find.text('No tools match this selection.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [780.0, 1180.0]) {
    testWidgets(
      'every workspace fits a ${width.toInt()}px Mac window with empty and selected states',
      (tester) async {
        tester.view.physicalSize = Size(width, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final job = GuiJobController();
        addTearDown(job.dispose);
        for (final tool in ToolDefinition.tools) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: ToolWorkspace(
                  key: ValueKey(tool.id),
                  tool: tool,
                  paths: const [],
                  job: job,
                  outputDirectory: '/tmp/results',
                  remember: false,
                  onBack: () {},
                  onPick: () async {},
                  onChooseOutput: () async {},
                  onPathsChanged: (_) {},
                  onOpen: (_, {bool reveal = false}) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tool.title);
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('run-tool')))
                .onPressed,
            isNull,
            reason: tool.title,
          );
        }
      },
    );
  }
}
