import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';

class CloseShiftResponse {
  final bool success;
  final bool queued;
  final String message;
  final int? insertId;
  final String? startTime;
  final String? endTime;
  final double openingBalance;
  final double totalSales;
  final double totalExpenses;
  final double netProfit;
  final double closingBalance;

  CloseShiftResponse({
    required this.success,
    this.queued = false,
    required this.message,
    this.insertId,
    this.startTime,
    this.endTime,
    this.openingBalance = 0.0,
    this.totalSales = 0.0,
    this.totalExpenses = 0.0,
    this.netProfit = 0.0,
    this.closingBalance = 0.0,
  });

  factory CloseShiftResponse.fromJson(Map<String, dynamic> json) {
    return CloseShiftResponse(
      success: json['success'] == true || json['success'] == 1,
      queued: json['queued'] == true,
      message: json['message']?.toString() ?? '',
      insertId: json['insert_id'] is int
          ? json['insert_id'] as int
          : int.tryParse(json['insert_id']?.toString() ?? ''),
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
      openingBalance: _toDouble(json['opening_balance']),
      totalSales: _toDouble(json['total_sales']),
      totalExpenses: _toDouble(json['total_expenses']),
      netProfit: _toDouble(json['net_profit']),
      closingBalance: _toDouble(json['closing_balance']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

class ApiServiceClose_shieft {
  final String baseUrl;

  ApiServiceClose_shieft({this.baseUrl = 'local-sqlite'});

  String _format(dynamic value) {
    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
    }
    if (value is String) {
      DateTime? parsed = DateTime.tryParse(value);
      parsed ??= DateFormat('dd/MM/yyyy hh:mm a').tryParse(value);
      return parsed == null
          ? value
          : DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
    }
    throw 'time value must be DateTime or String';
  }

  DateTime? _parseDateTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed) ??
        DateTime.tryParse(trimmed.replaceFirst(' ', 'T')) ??
        DateFormat('yyyy-MM-dd HH:mm:ss').tryParse(trimmed) ??
        DateFormat('dd/MM/yyyy hh:mm a').tryParse(trimmed);
  }

  Future<CloseShiftResponse> closeShift({
    required String cashierName,
    required dynamic startTimeParam,
    required dynamic endTime,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final username = cashierName.trim();
    final sessionStart = _format(startTimeParam);
    final end = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    debugPrint(
        '[CloseShift] using fresh end=$end (ignoring passed endTime=$endTime)');
    await DBHelper.instance.ensureCurrentShiftStartDateTime(
      cashierName: username,
      fallbackStartTime: sessionStart,
    );
    final resolvedStart =
        await DBHelper.instance.getCurrentShiftStartDateTime(username);
    var start = resolvedStart;
    final parsedStart = _parseDateTime(start);
    final parsedEnd = _parseDateTime(end);
    final shouldUseSessionStart = start == '2000-01-01 00:00:00' ||
        (parsedStart != null &&
            parsedEnd != null &&
            parsedEnd.difference(parsedStart).inHours > 48);
    if (shouldUseSessionStart) {
      start = sessionStart;
      debugPrint(
          '[CloseShift] overriding start with sessionStart=$sessionStart');
    }
    debugPrint(
        '[CloseShift] username=$username sessionStart=$sessionStart resolvedStart=$resolvedStart start=$start end=$end overriddenBySessionStart=$shouldUseSessionStart');
    final db = await DBHelper.instance.database;
    final diag = await db.rawQuery(
      "SELECT COUNT(*) as cnt, MIN(date) as min_d, MAX(date) as max_d FROM sales WHERE TRIM(COALESCE(cashier_username,''))=?",
      [username],
    );
    debugPrint('[CloseShift] sales for cashier: ${diag.first}');
    final diagRange = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM sales WHERE TRIM(COALESCE(cashier_username,''))=? AND datetime(date) BETWEEN datetime(?) AND datetime(?)",
      [username, start, end],
    );
    debugPrint(
        '[CloseShift] sales in range [$start -> $end]: ${diagRange.first}');
    final summary = await DBHelper.instance.computeCloseShiftSummary(
      cashierName: username,
      fromDateTime: start,
      toDateTime: end,
    );
    final openingBalance = summary['opening_balance'] ?? 0.0;
    final totalSales = summary['total_sales'] ?? 0.0;
    final totalExpenses = summary['total_expenses'] ?? 0.0;
    final netProfit = summary['net_profit'] ?? (totalSales - totalExpenses);
    final closingBalance = summary['closing_balance'] ?? openingBalance;

    final id = await DBHelper.instance.closeShiftAndResetDrawer(
      cashierName: username,
      startTime: start,
      endTime: end,
      openingBalance: openingBalance,
      totalSales: totalSales,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
      closingBalance: closingBalance,
      fromDateTime: start,
      toDateTime: end,
    );
    return CloseShiftResponse(
      success: true,
      queued: false,
      message: 'Saved locally',
      insertId: id,
      startTime: start,
      endTime: end,
      openingBalance: openingBalance,
      totalSales: totalSales,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
      closingBalance: closingBalance,
    );
  }

  Future<void> migrateOldCloseShiftOps() async {}
}
