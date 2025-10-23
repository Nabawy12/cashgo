// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

class CloseShiftResponse {
  final bool success;
  final bool queued; // لو العملية خُزّنت محليًا للرفع لاحقًا
  final String message;
  final int? insertId;
  final String? startTime;
  final String? endTime;

  CloseShiftResponse({
    required this.success,
    this.queued = false,
    required this.message,
    this.insertId,
    this.startTime,
    this.endTime,
  });

  factory CloseShiftResponse.fromJson(Map<String, dynamic> json) {
    return CloseShiftResponse(
      success: json['success'] == true || json['success'] == 1,
      queued: json['queued'] == true,
      message: json['message']?.toString() ?? '',
      insertId: json.containsKey('insert_id')
          ? (json['insert_id'] is int ? json['insert_id'] : int.tryParse(json['insert_id'].toString()))
          : null,
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
    );
  }
}

class ApiServiceClose_shieft {
  final String baseUrl;

  ApiServiceClose_shieft({this.baseUrl = 'https://nabawisolution.com'});

  /// closeShift: startTimeParam يمكن يكون DateTime أو String.
  /// لو الجهاز اوفلاين، يتم حفظ operation في صندوق 'ops' ليتم رفعه لاحقًا بواسطة SyncManager.
  Future<CloseShiftResponse> closeShift({
    required String cashierName,
    required dynamic startTimeParam,
    required dynamic endTime,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final endpoint = '$baseUrl/close_shift.php';

    // تحويل القيم إلى String بصيغة مناسبة إن أمكن
    String formattedStart;
    String formattedEnd;

    // --- format start ---
    if (startTimeParam is DateTime) {
      formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(startTimeParam);
    } else if (startTimeParam is String) {
      try {
        final parsed = DateTime.parse(startTimeParam);
        formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
      } catch (_) {
        try {
          final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parseLoose(startTimeParam);
          formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
        } catch (_) {
          formattedStart = startTimeParam;
        }
      }
    } else {
      return CloseShiftResponse(success: false, queued: false, message: 'startTimeParam must be DateTime or String');
    }

    // --- format end ---
    if (endTime is DateTime) {
      formattedEnd = DateFormat('yyyy-MM-dd HH:mm:ss').format(endTime);
    } else if (endTime is String) {
      try {
        final parsed = DateTime.parse(endTime);
        formattedEnd = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
      } catch (_) {
        try {
          final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parseLoose(endTime);
          formattedEnd = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
        } catch (_) {
          formattedEnd = endTime;
        }
      }
    } else {
      return CloseShiftResponse(success: false, queued: false, message: 'endTime must be DateTime or String');
    }

    final bodyMap = {
      'cashier_name': cashierName,
      'start_time': formattedStart,
      'end_time': formattedEnd,
    };

    try {
      final conn = await Connectivity().checkConnectivity();
      final online = conn != ConnectivityResult.none;

      if (!online) {
        // اوفلاين -> خزن كـ op. خلي priority عالي و asForm true عشان يروح آخر حاجة وبنفس فورم السيرفر
        try {
          final opsBox = await Hive.openBox('ops');
          final opId = DateTime.now().millisecondsSinceEpoch.toString();
          final op = {
            'opId': opId,
            'entity': 'close_shift',
            'type': 'api',
            'method': 'POST',
            'endpoint': endpoint,
            'asForm': true,
            'priority': 999,
            'body': bodyMap,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'state': 'pending',
            'retries': 0,
          };
          await opsBox.put(opId, op);
          debugPrint('[ApiServiceClose_shieft] queued close_shift opId=$opId body=$bodyMap');
          return CloseShiftResponse(
            success: true,
            queued: true,
            message: 'Queued locally; will be sent when connectivity is restored',
            insertId: null,
            startTime: formattedStart,
            endTime: formattedEnd,
          );
        } catch (e) {
          return CloseShiftResponse(success: false, queued: false, message: 'Failed to queue locally: $e');
        }
      }

      // Online -> send direct as form data
      final uri = Uri.parse(endpoint);
      final resp = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: bodyMap,
      )
          .timeout(timeout);

      if (resp.statusCode != 200) {
        return CloseShiftResponse(
          success: false,
          queued: false,
          message: 'HTTP ${resp.statusCode}: ${resp.reasonPhrase}\n${resp.body}',
        );
      }

      final jsonBody = json.decode(resp.body);
      if (jsonBody is Map<String, dynamic>) {
        return CloseShiftResponse.fromJson(jsonBody);
      } else {
        return CloseShiftResponse(success: false, queued: false, message: 'Invalid JSON response');
      }
    } on SocketException catch (e) {
      // لو حصل SocketException أثناء الإرسال -> خزّن كـ op بنفس الـflags
      try {
        final opsBox = await Hive.openBox('ops');
        final opId = DateTime.now().millisecondsSinceEpoch.toString();
        final op = {
          'opId': opId,
          'entity': 'close_shift',
          'type': 'api',
          'method': 'POST',
          'endpoint': endpoint,
          'asForm': true,
          'priority': 999,
          'body': bodyMap,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'state': 'pending',
          'retries': 0,
        };
        await opsBox.put(opId, op);
        debugPrint('[ApiServiceClose_shieft] SocketException -> queued close_shift opId=$opId body=$bodyMap');
        return CloseShiftResponse(
          success: true,
          queued: true,
          message: 'SocketException: queued locally',
          insertId: null,
          startTime: formattedStart,
          endTime: formattedEnd,
        );
      } catch (e2) {
        return CloseShiftResponse(success: false, queued: false, message: 'SocketException and failed to queue: $e / $e2');
      }
    } catch (e) {
      return CloseShiftResponse(success: false, queued: false, message: 'Request failed: $e');
    }
  }

  /// اختياري: نقدر نضيف وظيفة لمرة واحدة لتصحيح ops القديمة إذا عندك ops مخزنة بدون asForm/priority
  Future<void> migrateOldCloseShiftOps() async {
    final box = await Hive.openBox('ops');
    final keys = box.keys.toList();
    for (final k in keys) {
      final raw = box.get(k);
      if (raw == null) continue;
      try {
        final op = Map<String, dynamic>.from(raw as Map);
        final endpoint = (op['endpoint'] ?? '').toString().toLowerCase();
        final entity = (op['entity'] ?? '').toString().toLowerCase();
        if (entity == 'close_shift' || endpoint.contains('close_shift.php')) {
          op['asForm'] = true;
          op['priority'] = (op['priority'] as int?) ?? 999;
          await box.put(k, op);
          debugPrint('[migrateOldCloseShiftOps] fixed op $k');
        }
      } catch (e) {
        debugPrint('[migrateOldCloseShiftOps] failed for $k : $e');
      }
    }
  }
}
