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

  Future<CloseShiftResponse> closeShift({
    required String cashierName,
    required dynamic startTimeParam,
    required dynamic endTime,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final username = cashierName.trim();
    final sessionStart = _format(startTimeParam);
    final end = _format(endTime);
    await DBHelper.instance.ensureCurrentShiftStartDateTime(
      cashierName: username,
      fallbackStartTime: sessionStart,
    );
    final start =
        await DBHelper.instance.getCurrentShiftStartDateTime(username);
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
