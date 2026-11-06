// Screenshot-only entrypoint. Build with the skill's offline debug flags.
import 'package:flutter/widgets.dart';

import 'package:gymapp/main.dart' as app;
import 'package:gymapp/services/tutorial_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TutorialPreferences.finishIntro(skipTutorial: true);
  app.main();
}
