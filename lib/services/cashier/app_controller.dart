// lib/services/maintenance_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../utils/colors.dart';

class MaintenanceService {
  static bool _inMaintenance = false;
  static String _message = 'التطبيق متوقف للصيانة حالياً. حاول لاحقاً.';

  /// يفحص حالة الصيانة. إذا ipMachine لم يُمرَّر، سيحاول تحديده محلياً.
  /// Usage:
  ///   await MaintenanceService.checkAndHandle(context);
  ///   or
  ///   await MaintenanceService.checkAndHandle(context, ipMachine: 'my-hostname');
  static Future<void> checkAndHandle(BuildContext context, {String? ipMachine}) async {
    // إذا لم يُعطَ ipMachine، نحاول الحصول عليه محلياً
    if (ipMachine == null || ipMachine.trim().isEmpty) {
      try {
        ipMachine = Platform.localHostname;
      } catch (e) {
        if (kDebugMode) print('Failed to get Platform.localHostname: $e');
        ipMachine = 'unknown';
      }
    }

    // تأكد من non-null
    final ipToSend = ipMachine.trim();

    try {
      // بناء URI مع query parameters للتأكد أن السيرفر يستقبل ip_machine
      final uri = Uri.https(
        'nabawisolution.com',
        '/app_control.php',
        {
          'action': 'status',
          'ip_machine': ipToSend,
        },
      );

      if (kDebugMode) {
        print('[MaintenanceService] Request URI: $uri');
      }

      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('[MaintenanceService] Response status: ${res.statusCode}');
        print('[MaintenanceService] Response body: ${res.body}');
      }

      if (res.statusCode != 200 || res.body.isEmpty) {
        _inMaintenance = false;
        return;
      }

      final Map<String, dynamic> j = jsonDecode(res.body);

      // parse enabled robustly
      int enabled = 0;
      if (j['enabled'] is int) {
        enabled = j['enabled'] as int;
      } else if (j['enabled'] != null) {
        enabled = int.tryParse(j['enabled'].toString()) ?? 0;
      }

      final message = (j['message'] ?? '')?.toString() ?? '';

      // اذا السيرفر رجع ip_machine في الرد نتحقق من مطابقته (اختياري لكن مفيد)
      final returnedIp = j['ip_machine']?.toString();

      final bool ipMatches = (returnedIp == null || returnedIp.isEmpty) ? true : (returnedIp == ipToSend);

      if (enabled == 1 && ipMatches) {
        _inMaintenance = true;
        _message = message.isNotEmpty ? message : _message;

        // عرض الدايلوج في الــ next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showMaintenanceDialog(context);
        });
        return;
      } else {
        _inMaintenance = false;
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('[MaintenanceService] Error while checking maintenance: $e\n$st');
      }
      _inMaintenance = false;
    }
  }

  static bool get isInMaintenance => _inMaintenance;

  static void _showMaintenanceDialog(BuildContext context) {
    // لو مش mounted أو already showing ممكن تضيف منطق لمنع التكرار (تبسيط هِنا)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: SizedBox(
            width: 300,
            height: 200,
            child: AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  _message,
                  style: const TextStyle(color: Colors.white),
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
