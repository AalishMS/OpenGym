import 'package:shared_preferences/shared_preferences.dart';

/// Bump when the disclosure text changes, so every user is asked again.
const int kCoachDisclosureVersion = 1;

/// Whether a user accepted the Coach's first-use disclosure, including the
/// age confirmation. Stored per user and per disclosure version.
class CoachDisclosure {
  const CoachDisclosure._();

  static String _key(String userId) =>
      'coach_disclosure_v${kCoachDisclosureVersion}_$userId';

  static Future<bool> isAccepted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> accept(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
