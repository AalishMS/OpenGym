import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/services/tutorial_preferences.dart';

void main() {
  Future<void> waitForSettingsLoad(SettingsProvider settings) async {
    final loaded = Completer<void>();
    settings.addListener(() {
      if (!loaded.isCompleted) loaded.complete();
    });
    await loaded.future;
  }

  test('fresh installs follow the system appearance and use cyan', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsProvider();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.accentIndex, SettingsProvider.defaultAccentIndex);
    expect(settings.accentSeed, const Color(0xFF41B9B9));

    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.accentIndex, SettingsProvider.defaultAccentIndex);
    expect(settings.accentSeed, const Color(0xFF41B9B9));
  });

  test('a new install still in the intro starts on system and keeps it '
      'after finishing the intro', () async {
    SharedPreferences.setMockInitialValues({});
    // The order `main` uses: record the intro flag, then settle the theme.
    expect(await TutorialPreferences.loadIntroPending(), isTrue);
    expect(await SettingsProvider.resolveStoredThemeMode(), ThemeMode.system);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('theme_mode'), ThemeMode.system.index);

    // Finishing the intro makes the install look used; the stored choice
    // must win so the next launch does not fall back to light.
    await TutorialPreferences.finishIntro();
    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);
    expect(settings.themeMode, ThemeMode.system);
  });

  test('an existing install that never chose a theme stays light', () async {
    // An update: the intro was finished long ago, no theme was ever saved.
    SharedPreferences.setMockInitialValues({
      TutorialPreferences.introPendingKey: false,
      'idkey_migration_v1_done': true,
    });

    expect(await SettingsProvider.resolveStoredThemeMode(), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('theme_mode'), ThemeMode.light.index);

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);
    expect(settings.themeMode, ThemeMode.light);
  });

  test('an install from before the intro flag stays light', () async {
    // Only the Hive migration marker exists; the intro flag was never set.
    SharedPreferences.setMockInitialValues({'idkey_migration_v1_done': true});

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('theme_mode'), ThemeMode.light.index);
  });

  test('saved appearance choices override first-run defaults', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': ThemeMode.dark.index,
      'accent_color': 0,
      TutorialPreferences.introPendingKey: true,
    });

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.accentIndex, 0);
    expect(settings.accentSeed, const Color(0xFF6AA9ED));
  });

  test('a saved system choice survives on an existing install', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': ThemeMode.system.index,
      TutorialPreferences.introPendingKey: false,
    });

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.system);
  });

  test('the Coach is off until the user turns it on', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);
    expect(settings.coachEnabled, isFalse);

    await settings.setCoachEnabled(true);
    final reloaded = SettingsProvider();
    await waitForSettingsLoad(reloaded);
    expect(reloaded.coachEnabled, isTrue);
  });

  test('weights default to kilograms and a pounds choice persists', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);
    expect(settings.weightUnit, 'kg');

    await settings.setWeightUnit('lbs');
    final reloaded = SettingsProvider();
    await waitForSettingsLoad(reloaded);
    expect(reloaded.weightUnit, 'lbs');
  });

  test('a stored unit reads as kg or lbs and nothing else', () async {
    for (final (stored, expected) in [
      ('lbs', 'lbs'),
      ('lb', 'lbs'),
      ('kg', 'kg'),
      ('stone', 'kg'),
    ]) {
      SharedPreferences.setMockInitialValues({'weight_unit': stored});
      final settings = SettingsProvider();
      await waitForSettingsLoad(settings);
      expect(settings.weightUnit, expected, reason: stored);
    }

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);
    await settings.setWeightUnit('lb');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('weight_unit'), 'lbs');
  });
}
