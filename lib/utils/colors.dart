import 'package:flutter/material.dart';

import '../services/app_settings_controller.dart';

class _CurrentTheme {
  static bool get isLight =>
      AppSettingsController.themeMode.value == ThemeMode.light;
}

/// ألوان الوضع الفاتح
class AppColorsLight {
  static const Color mainColor = Color(0xff5465FF);
  static const Color bgColor = Color(0xffF7F8FC);
  static const Color iconColor = Colors.black;
  static const Color bgCardColor = Color(0xffFFFFFF);
  static const Color strokColor = Color(0xffd1d5db);
  static const Color successColor = Color(0xff27AF4D);
  static final Color iconTextFormColor = Colors.grey.shade400;
  static const Color iconBackColor = Color(0xfff5f6f7);
  static const Color rateColor = Color(0xffFFC412);
  static const Color bgSelected = Color(0xffeef0ff);
  static const Color offerSelected = Color(0xffFF4B4B);
  static const Color ongoing = Color(0xffff7456);
  static const Color accepted = Color(0xff48bffd);
  static const Color pending = Color(0xfffdb448);

  /// ألوان النصوص
  static const Color secondTextLight = Color(0xff424242);
  static const Color mainTextDark = Colors.black;
}

/// ألوان الوضع الغامق
class AppColorsDark {
  static const Color mainColor = Color(0xff5465FF);
  static Color get bgColor =>
      _CurrentTheme.isLight ? AppColorsLight.bgColor : const Color(0xff1A1C28);
  static Color get bgCardColor => _CurrentTheme.isLight
      ? AppColorsLight.bgCardColor
      : const Color(0xff262935);
  static Color get strokColor => _CurrentTheme.isLight
      ? AppColorsLight.strokColor
      : const Color(0xff3A3D48);

  /// ألوان النصوص
  static Color get mainTextLight =>
      _CurrentTheme.isLight ? Colors.grey.shade800 : const Color(0xff808B97);
  static Color get mainTextDark =>
      _CurrentTheme.isLight ? Colors.black : Colors.white;
}
