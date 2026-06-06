import 'package:flutter/material.dart';

import 'db/db_helper.dart';

class AppSettingsController {
  AppSettingsController._();

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> loadThemeMode() async {
    final pref = await DBHelper.instance.getThemePreference();
    themeMode.value = pref == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await DBHelper.instance
        .saveThemePreference(mode == ThemeMode.light ? 'light' : 'dark');
  }
}
