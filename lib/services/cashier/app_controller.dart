import 'dart:convert';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MaintenanceService {
  static bool _inMaintenance = false;
  static String _message = 'التطبيق متوقف للصيانة حالياً. حاول لاحقاً.';

  /// فحص حالة الصيانة من السيرفر
  static Future<void> checkAndHandle(BuildContext context) async {
    try {
      final res = await http.get(
        Uri.parse('https://nabawisolution.com/app_control.php'),
      );

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final j = jsonDecode(res.body);
        final enabled = (j['enabled'] ?? 0) as int;
        final message = (j['message'] ?? '') as String;

        if (enabled == 1) {
          _inMaintenance = true;
          _message = message.isNotEmpty ? message : _message;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showMaintenanceDialog(context);
          });
          return;
        }
      }
    } catch (e) {
      print('Failed to check maintenance: $e');
    }
    _inMaintenance = false;
  }

  static bool get isInMaintenance => _inMaintenance;

  static void _showMaintenanceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false, // ممنوع زر الرجوع
          child: SizedBox(
            width: 300,
            height: 200,
            child: AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title:Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                    _message,
                  style: TextStyle(color: Colors.white),
                ),
              ),
              actions: const [],
            ),
          ),
        );
      },
    );
  }
}
