import 'package:flutter/material.dart';

class MaintenanceService {
  static bool _inMaintenance = false;
  static const String _message = 'التطبيق يعمل  بدون اتصال بالخادم.';

  static Future<void> checkAndHandle(BuildContext context,
      {String? ipMachine}) async {
    _inMaintenance = false;
  }

  static bool get isInMaintenance => _inMaintenance;
  static String get message => _message;
}
