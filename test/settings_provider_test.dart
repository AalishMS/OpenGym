import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/providers/settings_provider.dart';

void main() {
  Future<void> waitForSettingsLoad(SettingsProvider settings) async {
    final loaded = Completer<void>();
    settings.addListener(() {
      if (!loaded.isCompleted) loaded.complete();
    });
    await loaded.future;
  }

  test('fresh installs default to light mode and cyan', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = SettingsProvider();

    expect(settings.themeMode, ThemeMode.light);
    expect(settings.accentIndex, SettingsProvider.defaultAccentIndex);
    expect(settings.accentSeed, const Color(0xFF00CED1));

    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.light);
    expect(settings.accentIndex, SettingsProvider.defaultAccentIndex);
    expect(settings.accentSeed, const Color(0xFF00CED1));
  });

  test('saved appearance choices override first-run defaults', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': ThemeMode.dark.index,
      'accent_color': 0,
    });

    final settings = SettingsProvider();
    await waitForSettingsLoad(settings);

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.accentIndex, 0);
    expect(settings.accentSeed, const Color(0xFF00A8FF));
  });
}
