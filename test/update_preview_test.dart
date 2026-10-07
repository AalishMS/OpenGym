import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/update_dialog.dart';

void main() {
  const previewEnabled = bool.fromEnvironment('OPENGYM_PREVIEW_UPDATE');

  testWidgets(
    'preview opens release notes and never starts an installation',
    (tester) async {
      final updates = UpdateProvider();
      addTearDown(updates.dispose);
      await updates.checkOnStartup();
      expect(updates.isPreview, isTrue);
      expect(updates.isUpdateAvailable, isTrue);

      Uri? openedUri;
      await tester.pumpWidget(
        ChangeNotifierProvider<UpdateProvider>.value(
          value: updates,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => showUpdateDialog(
                            context,
                            openRelease: (uri) async {
                              openedUri = uri;
                              return true;
                            },
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text("What's changed"), findsOneWidget);
      expect(find.text('Faster workout startup'), findsOneWidget);
      await tester.tap(find.text('View release on GitHub'));
      await tester.pump();
      expect(openedUri, updates.release!.releasePageUri);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(updates.status, UpdateStatus.available);
      expect(updates.isBusy, isFalse);
      expect(updates.error, isNull);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text("What's changed"), findsNothing);
      await updates.checkManually();
      expect(updates.isUpdateAvailable, isTrue);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text("What's changed"), findsOneWidget);
    },
    skip: !previewEnabled,
  );
}
