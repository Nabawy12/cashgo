// lib/screens/admin/admin_cash_drawer_page_network.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:skeletonizer/skeletonizer.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../models/login.dart';
import '../../services/Api/Admin/financle.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb & defaultTargetPlatform

/// شاشة الدرج — تدعم offline / online: تحفظ محليًا في Hive وتضع ops في صندوق 'ops'
/// لكي يقوم SyncManager لاحقًا برفعها عند عودة الاتصال.
class AdminCashDrawerPage extends StatefulWidget {
  const AdminCashDrawerPage({Key? key}) : super(key: key);

  @override
  State<AdminCashDrawerPage> createState() => _AdminCashDrawerPageState();
}

class _AdminCashDrawerPageState extends State<AdminCashDrawerPage> {
  final TextEditingController _startingController = TextEditingController();
  final TextEditingController _maxLimitController = TextEditingController();

  final NumberFormat _moneyFmt =
      NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  final NumberFormat _moneyFmtNoDecimal =
      NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  bool _loading = true;

  double _startingAmount = 0.0;
  double _maxLimit = 0.0;
  double _totalInDrawer = 0.0;
  double _salesNet = 0.0;
  double _salesWallet = 0.0; // sales paid by wallet/card
  double _purchasePaidCash = 0.0;
  double _purchasePaidWallet = 0.0;
  double _creditOutstanding = 0.0;
  double _purchasePaidOnCredit = 0.0;
  double _totalSalesAllShifts = 0.0;
  double _totalClosingBalanceAllShifts = 0.0;

  final InsertFinancialAccountService _service =
      InsertFinancialAccountService();
  List<CloseShift> _shifts = [];
  bool _loadingShifts = false;
  DateTime _selectedDate = DateTime.now();

  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadData().then((_) => _loadAllShiftsSummary());
    _loadShifts(date: _selectedDate);
  }

  @override
  void dispose() {
    _startingController.dispose();
    _maxLimitController.dispose();
    _service.dispose();
    super.dispose();
  }

  String _formatMoney(double value) {
    const eps = 0.000001;
    final isWhole = (value - value.truncate()).abs() < eps;
    return isWhole ? _moneyFmtNoDecimal.format(value) : _moneyFmt.format(value);
  }

  String _formatWithSign(double value) {
    if (value < 0) return '-${_formatMoney(value.abs())}';
    return _formatMoney(value);
  }

  void _showSnackBar(SnackBar snackBar) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: snackBar.content,
        duration: snackBar.duration,
        action: snackBar.action,
        backgroundColor: snackBar.backgroundColor,
        elevation: snackBar.elevation,
        shape: snackBar.shape,
        behavior: SnackBarBehavior.floating,
        margin: isLight
            ? const EdgeInsets.only(bottom: 80, left: 16, right: 16)
            : const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------------------
  // Offline/online helpers
  // ---------------------------
  Future<bool> _isOnline() async {
    try {
      final c = await Connectivity().checkConnectivity();
      return c != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveLocalAndQueue(FinancialAccount payload,
      {String? localKey, Map<String, dynamic>? extraMeta}) async {
    // open boxes
    final finBox = await Hive.openBox('financial_accounts');
    final opsBox = await Hive.openBox('ops');

    final lid = localKey ?? 'local_${DateTime.now().microsecondsSinceEpoch}';
    final record = payload.toJsonFull();
    // ensure created_at exists
    record['created_at'] =
        record['created_at'] ?? DateTime.now().toUtc().toIso8601String();
    record['sync_state'] = 'pending';
    record['local_id'] = lid;
    if (extraMeta != null) record.addAll(extraMeta);

    await finBox.put(lid, record);

    // create op for SyncManager
    final opId = _uuid.v4();
    final op = {
      'opId': opId,
      'entity': 'financial_account',
      'type': 'create',
      'payload': {...payload.toJsonForServer(), 'local_id': lid},
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'retries': 0,
    };

    await opsBox.put(opId, op);
  }

  Future<void> _saveServerRecordToLocal(Map<String, dynamic> serverData) async {
    final finBox = await Hive.openBox('financial_accounts');
    if (serverData['id'] != null) {
      final key = serverData['id'].toString();
      final toStore = Map<String, dynamic>.from(serverData);
      toStore['sync_state'] = 'synced';
      await finBox.put(key, toStore);
    } else {
      // fallback: store with generated id
      final key = 'local_${DateTime.now().microsecondsSinceEpoch}';
      final toStore = Map<String, dynamic>.from(serverData);
      toStore['sync_state'] = 'synced';
      await finBox.put(key, toStore);
    }
  }

  Future<FinancialAccount?> _latestFromLocal() async {
    final finBox = await Hive.openBox('financial_accounts');
    if (finBox.isEmpty) return null;

    // try to pick latest by created_at if available
    DateTime? bestDate;
    dynamic bestVal;
    for (final k in finBox.keys) {
      final v = finBox.get(k);
      if (v == null || v is! Map) continue;
      DateTime? created;
      try {
        if (v['created_at'] != null) {
          created = DateTime.tryParse(v['created_at'].toString());
        }
      } catch (_) {
        created = null;
      }
      if (created == null) {
        // fallback to insertion order: use numeric local id timestamp if present
        if (k is String && k.startsWith('local_')) {
          final parts = k.split('_');
          if (parts.length > 1) {
            final ts = int.tryParse(parts[1]);
            if (ts != null)
              created =
                  DateTime.fromMillisecondsSinceEpoch((ts / 1000).round());
          }
        }
      }
      if (created != null) {
        if (bestDate == null || created.isAfter(bestDate)) {
          bestDate = created;
          bestVal = v;
        }
      } else {
        // if no created dates at all, just keep the last value encountered
        bestVal = v;
      }
    }

    if (bestVal != null && bestVal is Map) {
      try {
        return FinancialAccount.fromJson(Map<String, dynamic>.from(bestVal));
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  // ---------------------------
  // Load data: try online then fallback to local
  // ---------------------------
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final online = await _isOnline();
    if (online) {
      // try fetch latest from server
      try {
        final list = await _service.getLatest(limit: 1);
        if (list.isNotEmpty) {
          final rec = list.first;
          // save server record to local cache for offline usage
          await _saveServerRecordToLocal(rec.toJsonFull());
          _applyRecordToState(rec);
          return;
        } else {
          // server returned empty -> try local cache
          final local = await _latestFromLocal();
          if (local != null) {
            _applyRecordToState(local);
            return;
          } else {
            // no data at all
            _applyDefaults();
            return;
          }
        }
      } catch (e, st) {
        debugPrint('Failed to load from server, will attempt local: $e\n$st');
        // fallthrough to local
      }
    }

    // offline or server failed: load local
    try {
      final local = await _latestFromLocal();
      if (local != null) {
        _applyRecordToState(local);
      } else {
        _applyDefaults();
      }
    } catch (e, st) {
      debugPrint('Failed to load local financial accounts: $e\n$st');
      _applyDefaults();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyDefaults() {
    if (!mounted) return;
    setState(() {
      _startingAmount = 0.0;
      _maxLimit = 0.0;
      _totalInDrawer = 0.0;
      _startingController.text = '0.00';
      _maxLimitController.text = '0.00';
      _loading = false;
    });
  }

  void _applyRecordToState(FinancialAccount rec) {
    if (!mounted) return;
    setState(() {
      _startingAmount = rec.startingAmount;
      _maxLimit = rec.maxLimit;
      _totalInDrawer = rec.totalInDrawer ?? 0.0;
      _startingController.text = _startingAmount.toStringAsFixed(2);
      _maxLimitController.text = _maxLimit.toStringAsFixed(2);
      _loading = false;
    });
  }

  Future<void> _loadAllShiftsSummary() async {
    if (!mounted) return;
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final db = await DBHelper.instance.database;
      await DBHelper.instance.ensureSaleColumns();
      await DBHelper.instance.ensureSaleReturnsColumns();

      final cashRows = await db.rawQuery('''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as cash_net
        FROM sales
        WHERE LOWER(TRIM(COALESCE(payment_method,''))) = 'cash'
          AND NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
          AND (
            (
              (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
              AND date(date) = ?
            )
            OR date(credit_paid_at) = ?
          )
      ''', [dateStr, dateStr]);
      final cashNet = cashRows.isNotEmpty && cashRows.first['cash_net'] != null
          ? (cashRows.first['cash_net'] as num).toDouble()
          : 0.0;

      final walletRows = await db.rawQuery('''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as wallet_net
        FROM sales
        WHERE LOWER(TRIM(COALESCE(payment_method,''))) IN ('wallet','card')
          AND NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
          AND (
            (
              (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
              AND date(date) = ?
            )
            OR date(credit_paid_at) = ?
          )
      ''', [dateStr, dateStr]);
      final walletNet =
          walletRows.isNotEmpty && walletRows.first['wallet_net'] != null
              ? (walletRows.first['wallet_net'] as num).toDouble()
              : 0.0;

      // diagnostic
      final allPurchases = await db.rawQuery(
          'SELECT id, payment_type, paid_amount, created_at FROM purchase_receipts ORDER BY created_at DESC LIMIT 10');
      debugPrint('[Purchases] all recent: $allPurchases');
      debugPrint('[Purchases] filtering by dateStr=$dateStr');

      final cashCheck = await db.rawQuery('''
        SELECT COUNT(*) as cnt, SUM(paid_amount) as total
        FROM purchase_receipts
        WHERE LOWER(TRIM(COALESCE(payment_type,''))) = 'cash'
      ''');
      debugPrint('[Purchases] cash without date filter: ${cashCheck.first}');

      final cashCheckWithDate = await db.rawQuery('''
        SELECT COUNT(*) as cnt, SUM(paid_amount) as total
        FROM purchase_receipts
        WHERE LOWER(TRIM(COALESCE(payment_type,''))) = 'cash'
          AND date(created_at) = ?
      ''', [dateStr]);
      debugPrint(
          '[Purchases] cash WITH date filter ($dateStr): ${cashCheckWithDate.first}');

      final purchaseCashRows = await db.rawQuery('''
        SELECT SUM(COALESCE(paid_cash, 0)) as purchase_cash
        FROM purchase_receipts
        WHERE date(created_at) = ?
      ''', [dateStr]);
      final purchaseCash = purchaseCashRows.isNotEmpty &&
              purchaseCashRows.first['purchase_cash'] != null
          ? (purchaseCashRows.first['purchase_cash'] as num).toDouble()
          : 0.0;

      final purchaseWalletRows = await db.rawQuery('''
        SELECT SUM(COALESCE(paid_wallet, 0)) as purchase_wallet
        FROM purchase_receipts
        WHERE date(created_at) = ?
      ''', [dateStr]);
      final purchaseWallet = purchaseWalletRows.isNotEmpty &&
              purchaseWalletRows.first['purchase_wallet'] != null
          ? (purchaseWalletRows.first['purchase_wallet'] as num).toDouble()
          : 0.0;

      final purchaseCreditRows = await db.rawQuery('''
        SELECT SUM(COALESCE(due_amount,0)) as purchase_due
        FROM purchase_receipts
        WHERE date(created_at) = ?
      ''', [dateStr]);
      final purchaseCredit = purchaseCreditRows.isNotEmpty &&
              purchaseCreditRows.first['purchase_due'] != null
          ? (purchaseCreditRows.first['purchase_due'] as num).toDouble()
          : 0.0;

      final diagRows = await db.rawQuery('''
        SELECT id, paid_delta, date FROM sale_returns
        ORDER BY id DESC LIMIT 5
      ''');
      debugPrint('[Returns Diagnostic] latest sale_returns: $diagRows');

      final returnsRows = await db.rawQuery('''
        SELECT SUM(COALESCE(paid_delta, 0)) as returns_total
        FROM sale_returns
        WHERE date(date) = ?
      ''', [dateStr]);
      final returnsTotal =
          returnsRows.isNotEmpty && returnsRows.first['returns_total'] != null
              ? (returnsRows.first['returns_total'] as num).toDouble()
              : 0.0;

      debugPrint('[Returns] returnsTotal=$returnsTotal for date=$dateStr');

      // paid_delta is negative when money is returned to customer,
      // so we add it here (adding a negative value subtracts it).
      final cashNetAfterReturns = cashNet + returnsTotal;

      final creditRows = await db.rawQuery('''
        SELECT SUM(COALESCE(total,0) - COALESCE(paid_amount,0)) as credit_outstanding
        FROM sales
        WHERE COALESCE(is_credit,0) = 1
          AND NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
          AND date(date) = ?
      ''', [dateStr]);
      final creditOutstanding = creditRows.isNotEmpty &&
              creditRows.first['credit_outstanding'] != null
          ? (creditRows.first['credit_outstanding'] as num).toDouble()
          : 0.0;

      final openingBalance =
          await DBHelper.instance.getFixedShiftOpeningBalance();
      final drawerNow = openingBalance + cashNetAfterReturns - purchaseCash;
      final walletTotal = walletNet - purchaseWallet;

      debugPrint(
          '[AllShiftsSummary] date=$dateStr cash=$cashNet returns=$returnsTotal cashAfterReturns=$cashNetAfterReturns wallet=$walletNet purchaseWallet=$purchaseWallet walletTotal=$walletTotal purchaseCash=$purchaseCash purchaseCredit=$purchaseCredit creditOutstanding=$creditOutstanding opening=$openingBalance drawer=$drawerNow');

      if (!mounted) return;
      setState(() {
        _salesNet = cashNetAfterReturns;
        _salesWallet = walletTotal;
        _purchasePaidCash = purchaseCash;
        _purchasePaidWallet = purchaseWallet;
        _purchasePaidOnCredit = purchaseCredit;
        _creditOutstanding = creditOutstanding;
        _startingAmount = openingBalance;
        _totalInDrawer = drawerNow;
        _startingController.text = _startingAmount.toStringAsFixed(2);
      });
    } catch (e, st) {
      debugPrint('Failed to load all shifts financial summary: $e\n$st');
    }
  }

  // ---------- Save helpers that try online, else queue ----------
  Future<void> _saveOnlineOrQueue(FinancialAccount payload) async {
    final online = await _isOnline();

    if (online) {
      try {
        final inserted = await _service.insert(payload);
        // server returned inserted record; persist locally and update UI
        // InsertFinancialAccountService.insert returns FinancialAccount.fromJson(...)
        // Save server record into Hive
        await _saveServerRecordToLocal(inserted.toJsonFull());
        _applyRecordToState(inserted);
        if (mounted) {
          _showSnackBar(const SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('تم الحفظ'),
            ),
            duration: Duration(seconds: 2),
          ));
        }
        return;
      } catch (e) {
        // network/API error -> fallthrough to queue
        debugPrint(
            '[AdminCashDrawerPage] online save failed, queueing locally: $e');
      }
    }

    // offline or failed: save local and queue op
    await _saveLocalAndQueue(payload);
    if (mounted) {
      _showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
              'لا يوجد اتصال — تم الحفظ محليًا وسيتم رفعه تلقائيًا عند عودة الشبكة'),
        ),
        duration: Duration(seconds: 3),
      ));
    }
    // update UI to reflect local change
    final localLatest = await _latestFromLocal();
    if (localLatest != null) _applyRecordToState(localLatest);
  }

  // ---------- دوال الحفظ المستخدمة في الواجهة ----------
  Future<void> _saveStartingAmount_replace() async {
    final text = _startingController.text.trim().replaceAll(',', '');
    final entered = double.tryParse(text) ?? 0.0;

    setState(() => _loading = true);
    try {
      final payload = FinancialAccount(
        startingAmount: entered,
        maxLimit: _maxLimit,
      );

      await _saveOnlineOrQueue(payload);
      await DBHelper.instance.setFixedShiftOpeningBalance(entered);
      await DBHelper.instance.setDrawerStartingAmount(
        entered,
        'admin',
        note: 'Fixed opening balance for every shift',
      );
      if (mounted) {
        setState(() {
          _startingAmount = entered;
          _startingController.text = entered.toStringAsFixed(2);
        });
      }
    } catch (e) {
      debugPrint('Error saving starting amount: $e');
      if (mounted) {
        _showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('خطأ أثناء الحفظ: $e'),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveMaxLimit() async {
    final text = _maxLimitController.text.trim().replaceAll(',', '');
    final enteredMax = double.tryParse(text) ?? 0.0;

    setState(() => _loading = true);
    try {
      final payload = FinancialAccount(
        startingAmount: _startingAmount,
        maxLimit: enteredMax,
      );

      await _saveOnlineOrQueue(payload);
    } catch (e) {
      debugPrint('Error saving max limit: $e');
      if (mounted)
        _showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('خطأ أثناء الحفظ: $e'),
          ),
        ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------ بقية الكود كما كان مع بعض التحسينات البسيطة ------------------

  Widget _buildSummaryRow(String label, double value,
      {TextStyle? style, IconData? icon, Color? color}) {
    final formatted = _formatMoney(value.abs());
    final sign = value < 0 ? '-' : '';
    final accent = color ?? AppColorsDark.mainTextDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 13)),
              ],
            ),
            Text('$sign$formatted',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ---------- شيفتات ----------
  Future<void> _loadShifts(
      {DateTime? date, bool tryWithoutDateIfEmpty = false}) async {
    final d = date ?? _selectedDate;
    if (!mounted) return;
    setState(() {
      _loadingShifts = true;
      _selectedDate = d;
    });

    try {
      final rows = await DBHelper.instance.getCloseShifts();
      final filtered = rows.where((row) {
        final parsed = _extractRecordDateFromMap(row);
        return parsed != null &&
            parsed.year == d.year &&
            parsed.month == d.month &&
            parsed.day == d.day;
      }).map((row) {
        final raw = Map<String, dynamic>.from(row);
        final date = _extractRecordDateFromMap(raw);
        return CloseShift(
          cashierName: (row['cashier_name'] ?? '').toString(),
          date: date,
          startTime: (row['start_time'] ?? '').toString(),
          endTime: (row['end_time'] ?? '').toString(),
          openingBalance: _pickDoubleFromMap(raw, ['opening_balance']) ?? 0.0,
          totalSales: _pickDoubleFromMap(raw, ['total_sales']) ?? 0.0,
          totalExpenses: _pickDoubleFromMap(raw, ['total_expenses']) ?? 0.0,
          netProfit: _pickDoubleFromMap(raw, ['net_profit']) ?? 0.0,
          closingBalance: _pickDoubleFromMap(raw, ['closing_balance']) ?? 0.0,
          raw: raw,
        );
      }).toList();
      final totalGrossSales = filtered.fold(0.0, (sum, row) {
        final raw2 = Map<String, dynamic>.from(row.raw ?? const {});
        final sales = (_pickDoubleFromMap(raw2, ['gross_sales']) ??
                _pickDoubleFromMap(raw2, ['total_sales']) ??
                row.totalSales)
            .clamp(0.0, double.infinity);
        return sum + sales;
      });

      final totalReturnsAllShifts = filtered.fold(0.0, (sum, row) {
        final raw2 = Map<String, dynamic>.from(row.raw ?? const {});
        final returnsDeltaRaw =
            _pickDoubleFromMap(raw2, ['returns_delta']) ?? 0.0;
        return sum + returnsDeltaRaw.abs();
      });

      final totalSalesAllShifts =
          (totalGrossSales - totalReturnsAllShifts).clamp(0.0, double.infinity);
      final totalExpensesAllShifts = filtered.fold(
          0.0,
          (sum, row) =>
              sum +
              (_pickDoubleFromMap(
                      Map<String, dynamic>.from(row.raw ?? const {}),
                      ['total_expenses']) ??
                  row.totalExpenses));
      var totalClosingBalanceAllShifts =
          totalSalesAllShifts - totalExpensesAllShifts;
      if (totalClosingBalanceAllShifts < 0) {
        totalClosingBalanceAllShifts = 0.0;
      }
      debugPrint(
          '[FinancialAccounts] loaded ${filtered.length} shifts for ${_dateFormat.format(d)} totalSalesAll=$totalSalesAllShifts totalExpensesAll=$totalExpensesAllShifts totalClosingAll=$totalClosingBalanceAllShifts');
      if (mounted) {
        setState(() {
          _shifts = filtered;
          _totalSalesAllShifts = totalSalesAllShifts;
          _totalClosingBalanceAllShifts = totalClosingBalanceAllShifts;
        });
        await _loadAllShiftsSummary();
      }
    } catch (e, st) {
      debugPrint('Failed to load close shifts: $e\n$st');
      if (mounted) {
        _showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('فشل تحميل تقفيلات الشيفت: $e',
                textAlign: TextAlign.right),
          ),
        ));
        setState(() => _shifts = []);
      }
    } finally {
      if (mounted) setState(() => _loadingShifts = false);
    }
  }

  DateTime? _extractRecordDateFromMap(Map m) {
    if (m.isEmpty) return null;
    final candidates = [
      'date',
      'shift_date',
      'created_at',
      'created',
      'date_time',
      'start_time',
      'end_time',
      'start_date',
      'end_date',
      'day',
      'timestamp',
      'time'
    ];

    for (final key in candidates) {
      if (!m.containsKey(key) || m[key] == null) continue;
      final val = m[key];
      if (val is num) {
        final n = val.toInt();
        if (n > 1000000000000) {
          try {
            return DateTime.fromMillisecondsSinceEpoch(n);
          } catch (_) {}
        } else if (n > 1000000000) {
          try {
            return DateTime.fromMillisecondsSinceEpoch(n * 1000);
          } catch (_) {}
        }
      }

      if (val is String) {
        final s = val.trim();
        if (s.isEmpty) continue;
        try {
          return DateTime.parse(s);
        } catch (_) {}
        try {
          return DateFormat('yyyy-MM-dd').parseLoose(s);
        } catch (_) {}
        try {
          return DateFormat('dd/MM/yyyy').parseLoose(s);
        } catch (_) {}
        try {
          return DateFormat('dd-MM-yyyy').parseLoose(s);
        } catch (_) {}
        try {
          return DateFormat('yyyy/MM/dd').parseLoose(s);
        } catch (_) {}
        final patterns = [
          'yyyy-MM-dd HH:mm:ss',
          'yyyy-MM-dd HH:mm',
          'dd/MM/yyyy HH:mm:ss',
          'dd/MM/yyyy HH:mm',
          'MM/dd/yyyy HH:mm:ss',
          'MM/dd/yyyy'
        ];
        for (final p in patterns) {
          try {
            return DateFormat(p).parseLoose(s);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  Future<void> _processShiftsResponse(String body, DateTime d) async {
    List<dynamic> listData = [];
    try {
      final decoded = json.decode(body);
      if (decoded is List) {
        listData = decoded;
      } else if (decoded is Map) {
        if (decoded.containsKey('rows') && decoded['rows'] is List) {
          listData = decoded['rows'];
        } else if (decoded.containsKey('data') && decoded['data'] is List) {
          listData = decoded['data'];
        } else if (decoded.containsKey('items') && decoded['items'] is List) {
          listData = decoded['items'];
        } else {
          final possible =
              decoded.values.firstWhere((v) => v is List, orElse: () => null);
          if (possible is List) listData = possible;
        }
      } else {
        if (mounted)
          _showSnackBar(SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('استجابة غير متوقعة. راجع اللوغ.',
                  textAlign: TextAlign.right),
            ),
          ));
        if (mounted) setState(() => _shifts = []);
        return;
      }
    } catch (e) {
      debugPrint('JSON decode failed: $e');
      if (mounted) {
        _showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('تعذر فك JSON: $e', textAlign: TextAlign.right),
          ),
        ));
        setState(() => _shifts = []);
      }
      return;
    }

    final shifts = <CloseShift>[];
    double totalDrawerSum = 0.0;
    double totalCreditSum = 0.0;
    double totalSalesCash = 0.0;
    double totalPurchasesPaidCash = 0.0;
    double totalPurchasesPaidOnCredit = 0.0;

    for (final e in listData) {
      if (e is Map) {
        final name = _pickStringFromMap(
            e, ['cashier_name', 'cashier', 'name', 'username', 'user']);
        final drawer = _pickDoubleFromMap(e, [
              'total_in_drawer',
              'total_in_cash',
              'drawer_total',
              'total_drawer',
              'total_inbox',
              'in_drawer'
            ]) ??
            0.0;

        final salesCash = _pickDoubleFromMap(e, [
              'profit_value_cash',
              'profit_cash',
              'sales_cash',
              'cash_sales',
              'net_cash',
              'profit_value'
            ]) ??
            0.0;

        final purchasesPaidCash = _pickDoubleFromMap(e, [
              'purchases_paid',
              'purchases_paid_cash',
              'purchases_cash_paid'
            ]) ??
            0.0;

        double purchasesPaidOnCredit = 0.0;
        final creditPaidKeys = [
          'purchases_credit_paid',
          'purchases_paid_on_credit',
          'paid_on_credit',
          'credit_paid',
          'paid_credit',
          'purchases_paid_credit',
          'purchases_paid_on_credit',
          'purchases_paid_credit_amount',
          'purchases_paid_credit_cash'
        ];
        for (final k in creditPaidKeys) {
          final v = _pickDoubleFromMap(e, [k]);
          if (v != null && v != 0.0) {
            purchasesPaidOnCredit = v;
            break;
          }
        }

        if (purchasesPaidOnCredit == 0.0) {
          final totalPaidPossible = _pickDoubleFromMap(e, [
            'purchases_paid_total',
            'purchases_total_paid',
            'purchases_paid',
            'purchases_total'
          ]);
          final paidCashPossible = _pickDoubleFromMap(e,
              ['purchases_paid_cash', 'purchases_cash_paid', 'purchases_cash']);
          if (totalPaidPossible != null && paidCashPossible != null) {
            purchasesPaidOnCredit = totalPaidPossible - paidCashPossible;
          }
        }

        if (purchasesPaidOnCredit == 0.0) {
          for (final entry in e.entries) {
            final key = entry.key.toString().toLowerCase();
            if ((key.contains('credit') &&
                    (key.contains('paid') || key.contains('payment'))) ||
                ((key.contains('purchase') ||
                        key.contains('purchas') ||
                        key.contains('purchases')) &&
                    key.contains('credit'))) {
              final val = entry.value;
              double? numVal;
              if (val is num)
                numVal = val.toDouble();
              else if (val is String) {
                final cleaned = val.replaceAll(',', '');
                numVal = double.tryParse(cleaned);
              }
              if (numVal != null && numVal != 0.0) {
                purchasesPaidOnCredit = numVal;
                break;
              }
            }
          }
        }

        if (purchasesPaidOnCredit.isNegative) purchasesPaidOnCredit = 0.0;

        final credit = _pickDoubleFromMap(e, [
              'cash_with_credit',
              'credit_outstanding',
              'total_credit',
              'due_amount',
              'outstanding',
              'credit_value',
              'credit'
            ]) ??
            0.0;

        shifts.add(CloseShift(
          cashierName: name ?? 'غير معروف',
          date: _extractRecordDateFromMap(e),
          startTime: _pickStringFromMap(e, ['start_time']) ?? '',
          endTime: _pickStringFromMap(e, ['end_time']) ?? '',
          openingBalance:
              _pickDoubleFromMap(e, ['opening_balance', 'starting_amount']) ??
                  0.0,
          totalSales:
              _pickDoubleFromMap(e, ['total_sales', 'sales_total']) ?? 0.0,
          totalExpenses:
              _pickDoubleFromMap(e, ['total_expenses', 'purchases_paid']) ??
                  0.0,
          netProfit: _pickDoubleFromMap(e, ['net_profit', 'profit']) ?? 0.0,
          closingBalance:
              _pickDoubleFromMap(e, ['closing_balance', 'total_in_drawer']) ??
                  drawer,
          raw: Map<String, dynamic>.from(e),
        ));

        totalDrawerSum += drawer;
        totalCreditSum += credit;
        totalSalesCash += salesCash;
        totalPurchasesPaidCash += purchasesPaidCash;
        totalPurchasesPaidOnCredit += purchasesPaidOnCredit;
      }
    }

    if (mounted) {
      setState(() {
        _shifts = shifts;
        _selectedDate = d;
        _totalInDrawer = totalDrawerSum;
        _creditOutstanding = totalCreditSum;
        _salesNet = totalSalesCash;
        _purchasePaidCash = totalPurchasesPaidCash;
        _purchasePaidOnCredit = totalPurchasesPaidOnCredit;
      });
    }

    if (shifts.isEmpty && listData.isNotEmpty) {
      debugPrint(
          'listData has entries but parser produced 0 shifts. First entry keys:');
      final first = listData.first;
      if (first is Map) {
        debugPrint(first.keys.toList().join(', '));
        if (mounted) {
          _showSnackBar(SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                  'الاستجابة تحتوي عناصر لكن المفاتيح غير متوقعة — راجع اللوغ (keys)',
                  textAlign: TextAlign.right),
            ),
          ));
        }
      }
    }
  }

  String? _pickStringFromMap(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k].toString();
    }
    return null;
  }

  double? _pickDoubleFromMap(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        final v = m[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final s = v.replaceAll(',', '');
          final d = double.tryParse(s);
          if (d != null) return d;
        }
      }
    }
    return null;
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return out;
  }

  Widget _buildCashierCard(CloseShift s) {
    final raw = s.raw ?? {};
    final cashierName = s.cashierName.isNotEmpty
        ? s.cashierName
        : (_pickStringFromMap(raw, ['cashier_name', 'cashier', 'name', 'username', 'user']) ?? 'غير معروف');
    final openingBalance = _pickDoubleFromMap(raw, ['opening_balance']) ?? s.openingBalance;
    final cashSales = _pickDoubleFromMap(raw, ['cash_sales_total', 'cash_sales', 'sales_cash']) ?? 0.0;
    final grossSales = (_pickDoubleFromMap(raw, ['gross_sales']) ?? s.totalSales).clamp(0.0, double.infinity);
    final totalSales = (_pickDoubleFromMap(raw, ['total_sales']) ?? grossSales).clamp(0.0, double.infinity);
    final unpaidCreditTotal = _pickDoubleFromMap(raw, ['unpaid_credit_total']) ?? 0.0;
    final walletSales = _pickDoubleFromMap(raw, ['wallet_sales_total', 'wallet_sales', 'sales_wallet']) ??
        (grossSales - cashSales).clamp(0.0, double.infinity);
    final cashExpenses = _pickDoubleFromMap(raw, ['cash_purchases', 'cash_expenses']) ?? 0.0;
    final totalExpenses = _pickDoubleFromMap(raw, ['total_expenses']) ?? s.totalExpenses;
    final returnsValue = (_pickDoubleFromMap(raw, ['returns_delta', 'returns_value']) ?? 0.0).abs();
    final walletExpenses = _pickDoubleFromMap(raw, ['wallet_purchases', 'wallet_expenses']) ??
        (totalExpenses - cashExpenses).clamp(0.0, double.infinity);
    final netProfit = totalSales - totalExpenses;
    final drawerBalance = totalSales - cashExpenses;

    String money(double value) => value.toStringAsFixed(2);
    Color signColor(double value) => value >= 0 ? Colors.greenAccent : Colors.redAccent;

    Widget chip(String label, String value, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 10)),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: signColor(netProfit).withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColorsDark.mainColor.withOpacity(0.15),
                        child: Icon(Icons.person, size: 16, color: AppColorsDark.mainColor),
                      ),
                      const SizedBox(width: 8),
                      Text(cashierName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text('${s.formattedStartTime} - ${s.formattedEndTime}',
                      style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  chip('مبدئي', money(openingBalance), AppColorsDark.mainTextLight),
                  chip('نقدي', money(cashSales), Colors.blueAccent),
                  chip('محفظة', money(walletSales), Colors.purpleAccent),
                  chip('إجمالي', money(grossSales), Colors.blueAccent),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  chip('مشتريات نقدي', money(cashExpenses), Colors.orangeAccent),
                  chip('مشتريات محفظة', money(walletExpenses), Colors.orangeAccent),
                  chip('مرتجعات', money(returnsValue), Colors.redAccent),
                  chip('آجلة غير مدفوعة', money(unpaidCreditTotal), Colors.amberAccent),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: signColor(netProfit).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الربح', style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 11)),
                        Text(money(netProfit),
                            style: TextStyle(color: signColor(netProfit), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('رصيد الدرج الآن', style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 11)),
                        Text(money(drawerBalance),
                            style: TextStyle(color: signColor(drawerBalance), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _desktopLayout(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth < 900 ? constraints.maxWidth : 1400.0;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 3,
                child: Card(
                  color: AppColorsDark.bgCardColor,
                  margin:
                      const EdgeInsets.only(right: 12.0, top: 8.0, bottom: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                              child: Text('تعيين المبلغ المبدئي في الدرج',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge!
                                      .copyWith(
                                          color: AppColorsDark.mainTextDark))),
                          const SizedBox(height: 20),
                          CustomFormField(
                            controller: _startingController,
                            hint: 'تعيين المبلغ المبدئي في الدرج',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                          const SizedBox(height: 20),
                          CustomButton(
                              text: 'حفظ القيمه للدرج',
                              onPressed: _saveStartingAmount_replace,
                              infinity: true,
                              color: AppColorsDark.mainColor.withOpacity(0.9)),
                          const SizedBox(height: 20),
                          Divider(height: 30, color: AppColorsDark.mainColor),
                          Center(
                              child: Text('ملخص سريع',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge!
                                      .copyWith(
                                          color: AppColorsDark.mainTextDark))),
                          const SizedBox(height: 10),
                          _buildSummaryRow('المبلغ في الدرج الآن', _totalInDrawer,
                              icon: Icons.account_balance_wallet_rounded, color: Colors.greenAccent),
                          _buildSummaryRow('صافي مبيعات نقدي', _salesNet,
                              icon: Icons.payments_rounded, color: Colors.blueAccent),
                          _buildSummaryRow('إجمالي المحفظة / البطاقة', _salesWallet,
                              icon: Icons.credit_card_rounded, color: Colors.purpleAccent),
                          _buildSummaryRow('مدفوعات مشتريات (نقدي)', _purchasePaidCash,
                              icon: Icons.shopping_cart_rounded, color: Colors.orangeAccent),
                          _buildSummaryRow('مدفوعات مشتريات (محفظة/بطاقة)', _purchasePaidWallet,
                              icon: Icons.shopping_cart_checkout_rounded, color: Colors.orangeAccent),
                          _buildSummaryRow('المدفوع (مشتريات آجلة)', _purchasePaidOnCredit,
                              icon: Icons.schedule_rounded, color: Colors.amberAccent),
                          const SizedBox(height: 10),
                          _buildSummaryRow('صافي مبيعات نقدي', _salesNet),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                              'إجمالي المحفظة / البطاقة', _salesWallet),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                              'مدفوعات مشتريات (نقدي)', _purchasePaidCash),
                          const SizedBox(height: 8),
                          _buildSummaryRow('مدفوعات مشتريات (محفظة/بطاقة)',
                              _purchasePaidWallet),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                              "المدفوع (مشتريات آجلة)", _purchasePaidOnCredit),
                          const SizedBox(height: 10),
                        ]),
                  ),
                ),
              ),
              Flexible(
                flex: 6,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                      child: Row(children: [
                        Expanded(
                          child: SizedBox(
                            height: 200,
                            child: _smallInfoCard(
                              'المبلغ في الدرج الآن = مبدئي + نقدي',
                              _formatWithSign(_totalInDrawer),
                              accent: Colors.greenAccent,
                              icon: Icons.account_balance_wallet_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 200,
                            child: _smallInfoCard(
                              'إجمالي المحفظة / البطاقة',
                              _formatWithSign(_maxLimit),
                              accent: Colors.blueAccent,
                              icon: Icons.wallet_outlined,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 15),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('تقفيلات الشيفت الخاصة بكل كاشير',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .copyWith(
                                            color: AppColorsDark.mainTextDark)),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: _pickDateAndReload,
                                      icon: Icon(Icons.calendar_today,
                                          color: Theme.of(context)
                                              .iconTheme
                                              .color),
                                      label: Text(
                                          _dateFormat.format(_selectedDate),
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      style: TextButton.styleFrom(
                                          backgroundColor: Colors.transparent),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () {
                                        _loadShifts(date: _selectedDate);
                                        _loadAllShiftsSummary();
                                      },
                                      icon: Icon(Icons.refresh,
                                          color: Theme.of(context)
                                              .iconTheme
                                              .color),
                                    )
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildShiftsGrid(constraints);
                              },
                            ),
                            const SizedBox(height: 12),
                          ]),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 12.0, top: 8.0, bottom: 8.0),
                      child: Row(children: [
                        Expanded(
                          child: SizedBox(
                            height: 200,
                            child: _allShiftsTotalsCard(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 200,
                            child: _smallInfoCard(
                              'الفواتير الاجله التي لم يتم دفعها',
                              _formatMoney(_creditOutstanding),
                              accent: Colors.orangeAccent,
                              icon: Icons.receipt_long_rounded,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // أعلى الملف: تأكد من وجود هذا الاستيراد

// داخل الState class: أضف/استبدل هذه الدوال والـ build بنسخهم الموضحة:

  bool _isMobilePlatform(BuildContext context, BoxConstraints constraints) {
    final platform = defaultTargetPlatform;
    final isNativeMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    // ضيق الشاشة = موبايل (حتى على الويب)
    final isNarrow = constraints.maxWidth < 700;

    return isNativeMobile || isNarrow;
  }

  Widget _mobileLayout(BoxConstraints constraints) {
    // نسخة مبسطة ومكدسة عمودياً من الواجهة لتناسب الشاشات الضيقة
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Center(
        child: ConstrainedBox(
          // limit عرض المحتوى لتبقى القراءة مريحة على تابلت كبير
          constraints: BoxConstraints(
              maxWidth: constraints.maxWidth.clamp(360.0, 900.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: AppColorsDark.bgCardColor,
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                            child: Text('تعيين المبلغ المبدئي في الدرج',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge!
                                    .copyWith(
                                        color: AppColorsDark.mainTextDark))),
                        const SizedBox(height: 12),
                        CustomFormField(
                          controller: _startingController,
                          hint: 'تعيين المبلغ المبدئي في الدرج',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                        const SizedBox(height: 12),
                        CustomButton(
                            text: 'حفظ القيمه للدرج',
                            onPressed: _saveStartingAmount_replace,
                            infinity: true,
                            color: AppColorsDark.mainColor.withOpacity(0.9)),
                        const SizedBox(height: 14),
                        Center(
                            child: Text(
                                'وضع الحد الاقسي لبدايه الدرج بعد تقفيل الشيفت',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge!
                                    .copyWith(
                                        color: AppColorsDark.mainTextDark),
                                textAlign: TextAlign.center)),
                        const SizedBox(height: 12),
                        CustomFormField(
                          controller: _maxLimitController,
                          hint: 'وضع الحد الاقصي لبدايه الدرج بعد تقفيل الشيفت',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                        const SizedBox(height: 12),
                        CustomButton(
                            text: 'حفظ الحد الأقصى',
                            onPressed: _saveMaxLimit,
                            infinity: true,
                            color: AppColorsDark.mainColor.withOpacity(0.7)),
                        const SizedBox(height: 16),
                        Divider(height: 20, color: AppColorsDark.mainColor),
                        const SizedBox(height: 8),
                        Center(
                            child: Text('ملخص سريع',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge!
                                    .copyWith(
                                        color: AppColorsDark.mainTextDark))),
                        const SizedBox(height: 8),
                        _buildSummaryRow(
                            'المبلغ في الدرج الآن', _totalInDrawer),
                        _buildSummaryRow('صافي مبيعات نقدي', _salesNet),
                        _buildSummaryRow(
                            'إجمالي المحفظة / البطاقة', _salesWallet),
                        _buildSummaryRow(
                            'مدفوعات مشتريات (نقدي)', _purchasePaidCash),
                        _buildSummaryRow('مدفوعات مشتريات (محفظة/بطاقة)',
                            _purchasePaidWallet),
                        _buildSummaryRow(
                            "المدفوع (مشتريات آجلة)", _purchasePaidOnCredit),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // بطاقات العرض العلوية (البديلة) — نجمعها في صفين في الموبايل
              Row(
                children: [
                  Expanded(
                      child: _smallInfoCard(
                          'المبلغ في الدرج الآن = مبدئي + نقدي',
                          _formatWithSign(_totalInDrawer))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 200,
                      child: Card(
                        elevation: 3,
                        color: AppColorsDark.bgCardColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                    child: Text('إجمالي المحفظة / البطاقة',
                                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                                            color: AppColorsDark.mainTextDark))),
                                const SizedBox(height: 12),
                                Expanded(
                                    child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text("جنيه",
                                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColorsDark.mainTextDark)),
                                          const SizedBox(width: 10),
                                          Text(_formatWithSign(_salesWallet),
                                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColorsDark.mainTextDark)),
                                        ])),
                              ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // شيفتات
              Card(
                color: AppColorsDark.bgCardColor,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('تقفيلات الشيفت',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge!
                                    .copyWith(
                                        color: AppColorsDark.mainTextDark)),
                            Row(children: [
                              TextButton.icon(
                                onPressed: _pickDateAndReload,
                                icon: Icon(Icons.calendar_today,
                                    color: Theme.of(context).iconTheme.color),
                                label: Text(_dateFormat.format(_selectedDate),
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark)),
                                style: TextButton.styleFrom(
                                    backgroundColor: Colors.transparent),
                              ),
                              IconButton(
                                onPressed: () {
                                  _loadShifts(date: _selectedDate);
                                  _loadAllShiftsSummary();
                                },
                                icon: Icon(Icons.refresh,
                                    color: Theme.of(context).iconTheme.color),
                              )
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (ctx, c) => _buildShiftsGrid(c)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // اجماليات سفلية
              Row(
                children: [
                  Expanded(child: _allShiftsTotalsCard()),
                ],
              ),
              const SizedBox(height: 12),
              _smallInfoCard('الفواتير الاجله التي لم يتم دفعها',
                  _formatMoney(_creditOutstanding)),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallInfoCard(String title, String value,
      {Color accent = Colors.greenAccent,
        IconData icon = Icons.account_balance_wallet_rounded}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColorsDark.bgCardColor, AppColorsDark.bgCardColor.withOpacity(0.6)],
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 16, color: accent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(color: AppColorsDark.mainTextDark),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(value,
                          style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 26)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _allShiftsTotalsCard() {
    Widget amountLine(String label, double value, Color color, IconData icon) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 12, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(_formatWithSign(value),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColorsDark.bgCardColor, AppColorsDark.bgCardColor.withOpacity(0.6)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.summarize_rounded, size: 18, color: AppColorsDark.mainColor),
                  const SizedBox(width: 6),
                  Text('الاجمالي في الدرج لكل الشيفتات',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    amountLine('إجمالي المبيعات', _totalSalesAllShifts, Colors.blueAccent, Icons.point_of_sale_rounded),
                    amountLine('صافي بعد المصروفات', _totalClosingBalanceAllShifts, Colors.greenAccent, Icons.account_balance_wallet_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        centerTitle: true,
        scrolledUnderElevation: 0.0,
        elevation: 0.0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text('الدرج والتقارير',
            style: TextStyle(fontSize: 27, color: AppColorsDark.mainTextDark)),
        actions: [
          IconButton(
            onPressed: () async {
              await _loadData();
              await _loadShifts(date: _selectedDate);
              await _loadAllShiftsSummary();
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Skeletonizer(
        enabled: _loading,
        enableSwitchAnimation: true,
        effect: ShimmerEffect(
          baseColor: AppColorsDark.mainColor,
          highlightColor: Colors.grey.shade600,
          duration: const Duration(seconds: 2),
        ),
        containersColor: AppColorsDark.bgCardColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_isMobilePlatform(context, constraints)) {
              return _mobileLayout(constraints);
            } else {
              return _desktopLayout(constraints);
            }
          },
        ),
      ),
    );
  }

  Widget _buildShiftsGrid(BoxConstraints constraints) {
    if (_shifts.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الرسالة الجديدة توضح أنه لا توجد تقفيلات لهذا اليوم مع عرض التاريخ
                Text(
                  'لا يوجد تقفيل شيفتات لهذا اليوم (${_dateFormat.format(_selectedDate)})',
                  style: TextStyle(
                      color: AppColorsDark.mainTextLight, fontSize: 17),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 35),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => _loadShifts(
                        date: _selectedDate.subtract(const Duration(days: 1)),
                      ),
                      child: Text(
                        'اليوم السابق',
                        style: TextStyle(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                          width: 2,
                        ),
                        foregroundColor:
                            Theme.of(context).brightness == Brightness.light
                                ? Colors.black
                                : Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        textStyle: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                    ),
                    OutlinedButton(
                      onPressed: () => _loadShifts(
                          date: _selectedDate.add(const Duration(days: 1))),
                      child: Text(
                        'اليوم التالي',
                        style: TextStyle(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                          width: 2,
                        ),
                        foregroundColor:
                            Theme.of(context).brightness == Brightness.light
                                ? Colors.black
                                : Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        textStyle: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loadingShifts) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_shifts.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'لا توجد تقفيلات في هذا التاريخ (${_dateFormat.format(_selectedDate)})',
                  style: TextStyle(color: AppColorsDark.mainTextLight),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () =>
                          _loadShifts(date: null, tryWithoutDateIfEmpty: false),
                      child: const Text('عرض جميع التقفيلات'),
                    ),
                    OutlinedButton(
                      onPressed: () => _loadShifts(
                          date:
                              _selectedDate.subtract(const Duration(days: 1))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).brightness == Brightness.light
                                ? Colors.black
                                : Colors.white,
                        side: BorderSide(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                      child: Text(
                        'اليوم السابق',
                        style: TextStyle(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _loadShifts(
                          date: _selectedDate.add(const Duration(days: 1))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).brightness == Brightness.light
                                ? Colors.black
                                : Colors.white,
                        side: BorderSide(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                      child: Text(
                        'اليوم التالي',
                        style: TextStyle(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // responsive: حد أقصى 3 في الصف، لكن لو المساحة ضيقة نخلي 1 أو 2
    final int perRow =
        constraints.maxWidth < 800 ? 1 : (constraints.maxWidth < 1200 ? 3 : 2);

    final rows = _chunk(_shifts, perRow);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.map((row) {
        // نبني قائمة عناصر الصف مع فواصل عرض 12 بين الكروت
        final List<Widget> children = [];
        for (var i = 0; i < row.length; i++) {
          children.add(Expanded(child: _buildCashierCard(row[i])));
          if (i != row.length - 1) children.add(const SizedBox(width: 12));
        }
        // إذا الصف فيه أقل من perRow نملأ الباقي بمساحات فارغة للحفاظ على التوزيع
        if (row.length < perRow) {
          for (var j = row.length; j < perRow; j++) {
            if (children.isNotEmpty) children.add(const SizedBox(width: 12));
            children.add(const Expanded(child: SizedBox()));
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _pickDateAndReload() async {
    DateTime? picked;
    try {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
    } catch (e, st) {
      debugPrint('showDatePicker error: $e\n$st');
      if (mounted) {
        _showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('خطأ في اختيار التاريخ — حاول مجدداً',
                textAlign: TextAlign.right),
          ),
        ));
      }
      return;
    }
    if (picked != null) {
      await _loadShifts(date: picked);
    }
  }
}

// ---------- نموذج بيانات لتقفيلة الشيفت ----------
class CloseShift {
  final String cashierName;
  final DateTime? date;
  final String startTime;
  final String endTime;
  final double openingBalance;
  final double totalSales;
  final double totalExpenses;
  final double netProfit;
  final double closingBalance;
  final Map<String, dynamic>? raw;

  CloseShift({
    required this.cashierName,
    this.date,
    this.startTime = '',
    this.endTime = '',
    this.openingBalance = 0.0,
    this.totalSales = 0.0,
    this.totalExpenses = 0.0,
    this.netProfit = 0.0,
    this.closingBalance = 0.0,
    this.raw,
  });

  String get formattedStartTime => _formatTime(startTime);
  String get formattedEndTime => _formatTime(endTime);

  static String _formatTime(String value) {
    if (value.trim().isEmpty) return '-';
    final parsed = DateTime.tryParse(value) ??
        DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return value;
    return DateFormat('hh:mm a').format(parsed);
  }
}
