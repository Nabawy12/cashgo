import 'package:cashgo/screens/admin/waletScreen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import 'AdminCreditPurchases.dart';
import 'AdminPaidPurchases.dart';
import 'package:cashgo/screens/admin/receipts.dart';
import 'package:cashgo/screens/admin/stock_screen.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';


// تأكد أن لديك استيراد DBHelper وComponents الأخرى في الملف الأصلي

class AdminCashDrawerPage extends StatefulWidget {
  const AdminCashDrawerPage({Key? key}) : super(key: key);

  @override
  State<AdminCashDrawerPage> createState() => _AdminCashDrawerPageState();
}

class _AdminCashDrawerPageState extends State<AdminCashDrawerPage> {
  final _drawerController = TextEditingController();
  bool _loading = true;
  double _startingAmount = 0.0;
  double _currentDrawer = 0.0;
  double _salesNet = 0.0;
  double _purchasePaidCash = 0.0;
  double _returnsDelta = 0.0;
  double _cardReceived = 0.0;
  double _creditOutstanding = 0.0;
  double _purchaseReceiptsOutstanding = 0.0;
  double _purchasePaid = 0.0;
  double _purchaseDue = 0.0;
  double _walletAmount = 0.0;
  double _cardTotalAvailable = 0.0;


  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  DateTime? _fromDate;
  DateTime? _toDate;

  final NumberFormat _moneyFmt = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  final NumberFormat _moneyFmtNoDecimal = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);

  String _formatMoney(double value) {
    const eps = 0.000001;
    final isWhole = (value - value.truncate()).abs() < eps;
    // Fixed: avoid recursive call. Use decimal format when needed.
    return isWhole ? _moneyFmtNoDecimal.format(value) : _moneyFmt.format(value);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _drawerController.dispose();
    _walletController.dispose();

    super.dispose();
  }
  Future<double> _getUntransferredCardAmountSafe({String? fromStr, String? toStr}) async {
    final dbHelper = DBHelper.instance;
    final db = await dbHelper.database;

    // check which columns exist
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final hasCardTransferredFlag = cols.any((c) => (c['name'] as String) == 'card_transferred');
    final hasTransferredAmount = cols.any((c) => (c['name'] as String) == 'card_transferred_amount');

    String dateCondition = '';
    List<Object?> args = ['card'];
    if (fromStr != null && toStr != null) {
      dateCondition = " AND date(date) BETWEEN ? AND ?";
      args.addAll([fromStr, toStr]);
    } else if (fromStr != null) {
      dateCondition = " AND date(date) >= ?";
      args.add(fromStr);
    } else if (toStr != null) {
      dateCondition = " AND date(date) <= ?";
      args.add(toStr);
    }

    String sql;
    if (hasTransferredAmount) {
      sql = '''
        SELECT SUM(
          (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(card_transferred_amount,0)
        ) as card_untransferred
        FROM sales
        WHERE payment_method = ?
          AND ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(card_transferred_amount,0)) > 0
        $dateCondition
      ''';
    } else if (hasCardTransferredFlag) {
      sql = '''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as card_untransferred
        FROM sales
        WHERE payment_method = ?
          AND COALESCE(card_transferred,0) = 0
        $dateCondition
      ''';
    } else {
      sql = '''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as card_untransferred
        FROM sales
        WHERE payment_method = ?
        $dateCondition
      ''';
    }

    final rows = await db.rawQuery(sql, args);
    final value = (rows.isNotEmpty && rows.first['card_untransferred'] != null)
        ? (rows.first['card_untransferred'] as num).toDouble()
        : 0.0;
    return value < 0 ? 0.0 : value;
  }

  double _cardNetSales = 0.0;
  final _walletController = TextEditingController();

  String _formatWithSign(double value) {
    if (value < 0) {
      return '-${_formatMoney(value.abs())}';
    }
    return _formatMoney(value);
  }
  double? _total;

  Future<void> _init() async {
    // تحميل المعاملات أولا (ستقوم بتحديث _loading و _grouped)
    // ثم احسب الإجمالي وحدّث الحالة لعرضه
    final total = await getTotalDrawerToWallet();
    setState(() {
      _total = total;
    });
  }

  Future<void> _loadData() async {
    _init();
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final dbHelper = DBHelper.instance;
      final db = await dbHelper.database;

      // تاريخ الفلترة
      final fromStr = _fromDate != null ? _dateFormat.format(_fromDate!) : null;
      final toStr = _toDate != null ? _dateFormat.format(_toDate!) : null;

      // البداية: المبلغ المبدئي
      final starting = await dbHelper.getLatestDrawerStartingAmount();

      // المجاميع الأساسية (نستخدم هذا للحقول الأخرى مثل returns_delta وغيرها)
      final totals = await dbHelper.getDrawerTotals(fromDate: fromStr, toDate: toStr);

      // ------ حساب صافي المبيعات النقدي بطريقة لا تعتمد على drawer_withdrawn_amount ------
      double salesNetCash = 0.0;
      try {
        String dateCondition = '';
        final List<Object?> args = <Object?>['cash'];
        if (fromStr != null && toStr != null) {
          dateCondition = " AND date(date) BETWEEN ? AND ?";
          args.addAll([fromStr, toStr]);
        } else if (fromStr != null) {
          dateCondition = " AND date(date) >= ?";
          args.add(fromStr);
        } else if (toStr != null) {
          dateCondition = " AND date(date) <= ?";
          args.add(toStr);
        }

        final rows = await db.rawQuery('''
        SELECT SUM( (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) ) AS sales_net_cash
        FROM sales
        WHERE payment_method = ? $dateCondition
      ''', args);

        salesNetCash = (rows.isNotEmpty && rows.first['sales_net_cash'] != null)
            ? (rows.first['sales_net_cash'] as num).toDouble()
            : 0.0;
        if (salesNetCash < 0) salesNetCash = 0.0;
      } catch (e) {
        debugPrint('Failed to compute salesNetCash directly: $e');
        // fallback to totals if direct query failed
        salesNetCash = (totals['sales_net_cash'] as num?)?.toDouble()
            ?? (totals['sales_net'] as num?)?.toDouble()
            ?? 0.0;
      }
      // -------------------------------------------------------------------------------------

      DateTime computeDate;
      if (_fromDate != null && _toDate != null) {
        final sameDay = _fromDate!.year == _toDate!.year &&
            _fromDate!.month == _toDate!.month &&
            _fromDate!.day == _toDate!.day;
        computeDate = sameDay ? _fromDate! : DateTime.now();
      } else {
        computeDate = DateTime.now();
      }

      double dailySalesTotal = 0.0;
      try {
        final summary = await DBHelper.instance.computeDailySummary(computeDate, excludeDrawerWithdrawn: true);
        dailySalesTotal = (summary['sales_total'] as double?) ?? 0.0;
      } catch (e) {
        debugPrint('Failed to compute daily summary: $e');
        dailySalesTotal = 0.0;
      }

      // الكرديت (مستحقات العملاء)
      final creditRows = await dbHelper.getCreditSales();
      double creditSum = 0.0;
      for (final r in creditRows) {
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
        creditSum += (total - paid);
      }

      // المستحق على الموردين (آجل)
      double purchaseReceiptsOutstanding = 0.0;
      try {
        final creditPurchaseReceipts = await dbHelper.getCreditPurchaseReceipts();
        for (final r in creditPurchaseReceipts) {
          purchaseReceiptsOutstanding += (r['due_amount'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (e) {
        debugPrint('Could not compute purchase receipts outstanding: $e');
        purchaseReceiptsOutstanding = 0.0;
      }

      // returnsDelta من totals (أو صفر)
      final returnsDelta = (totals['returns_delta'] as num?)?.toDouble() ?? 0.0;

      // صافي مبيعات الكارت
      double cardNetSales = 0.0;
      try {
        cardNetSales = await dbHelper.getNetCardSales(fromDate: fromStr, toDate: toStr);
      } catch (e) {
        debugPrint('Failed to get net card sales: $e');
        cardNetSales = 0.0;
      }

      // الكارت غير المحول
      double untransferredCard = 0.0;
      try {
        untransferredCard = await _getUntransferredCardAmountSafe(fromStr: fromStr, toStr: toStr);
      } catch (e) {
        debugPrint('Failed to get untransferred card amount: $e');
        untransferredCard = 0.0;
      }

      // ===== المشتريات المدفوعة كاش فقط =====
      double purchasePaidCash = 0.0;
      try {
        final rows = await db.rawQuery(
            "SELECT SUM(COALESCE(paid_amount,0)) AS total FROM purchase_receipts WHERE payment_type = 'cash'"
        );
        purchasePaidCash = (rows.isNotEmpty && rows.first['total'] != null)
            ? (rows.first['total'] as num).toDouble()
            : 0.0;
      } catch (e) {
        debugPrint('Failed to compute purchasePaidCash in _loadData: $e');
        try {
          final paidReceipts = await dbHelper.getPaidPurchaseReceipts();
          double sum = 0.0;
          for (final r in paidReceipts) {
            final type = r['payment_type'] as String? ?? 'cash';
            if (type == 'cash') sum += (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
          }
          purchasePaidCash = sum;
        } catch (e2) {
          debugPrint('Fallback also failed: $e2');
          purchasePaidCash = 0.0;
        }
      }

      // حساب القيمة الحالية للدرج (starting + مبيعات كاش - مشتريات كاش)
      final double computedFromParts = (salesNetCash == 0)
          ? (starting + salesNetCash)
          : (starting + (salesNetCash - _total!));
      final double adjustedCurrent = computedFromParts;

      // قراءة سندات الشراء لتعبئة paid/due
      final purchaseReceipts = await DBHelper.instance.getCreditPurchaseReceipts();
      double totalPaid = 0.0;
      double totalDue = 0.0;
      for (final r in purchaseReceipts) {
        totalPaid += (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
        totalDue  += (r['due_amount'] as num?)?.toDouble() ?? 0.0;
      }
      _purchasePaid = totalPaid;
      _purchaseDue = totalDue;

      // رصيد المحفظة
      double walletAmount = 0.0;
      try {
        await dbHelper.ensureCardWalletTable();
        walletAmount = await dbHelper.getLatestCardWalletAmount();
      } catch (e) {
        debugPrint('Could not read card_wallet: $e');
        walletAmount = 0.0;
      }

      // تحديث الحالة
      if (!mounted) return;
      setState(() {
        _startingAmount = starting;
        _currentDrawer = adjustedCurrent;
        _salesNet = salesNetCash; // <-- الآن يعرض المجموع بدون تأثير drawer_withdrawn_amount
        _cardReceived = untransferredCard;
        _walletAmount = walletAmount;
        _cardTotalAvailable = (_cardReceived) + (_walletAmount);

        _purchasePaidCash = purchasePaidCash;
        _returnsDelta = returnsDelta;
        _creditOutstanding = creditSum;
        _purchaseReceiptsOutstanding = purchaseReceiptsOutstanding;

        _cardNetSales = cardNetSales;

        _drawerController.text = _currentDrawer.toStringAsFixed(2);
        _walletController.text = _walletAmount.toStringAsFixed(2);
      });

    } catch (e, st) {
      debugPrint('Error loading drawer data: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تحميل البيانات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToWallet() async {
    final text = _walletController.text.trim();
    final entered = double.tryParse(text.replaceAll(',', '')) ?? 0.0;
    if (entered < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صالحًا (0 أو أكبر)')));
      return;
    }

    setState(() => _loading = true);
    try {
      final dbHelper = DBHelper.instance;
      await dbHelper.ensureCardWalletTable();

      // اقرأ الرصيد الحالي canonical
      final latestWallet = await dbHelper.getLatestCardWalletAmount();

      // حساب الفرق (ما يجب تسجيله في دفتر المحفظة)
      final delta = entered - latestWallet;

      if ((delta).abs() < 0.000001) {
        // لا تغيير فعلي
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الرصيد بالفعل EGP ${entered.toStringAsFixed(2)}')));
        return;
      }

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : 'admin';

      // سجّل الفرق (موجب أو سالب) ليجعل الرصيد = entered
      await dbHelper.changeCardWalletBy(delta, username, note: 'Set wallet to ${entered.toStringAsFixed(2)} (delta ${delta.toStringAsFixed(2)})');

      // تحديث UI محلي سريع
      _walletAmount = entered;
      _walletController.text = _walletAmount.toStringAsFixed(2);

      // إعادة حساب الكارد غير المحوّل ثم اجمالي المتاح
      final totalUntransferred = await _getUntransferredCardAmountSafe();
      setState(() {
        _cardTotalAvailable = _walletAmount + totalUntransferred;
      });

      // canonical reload للتأكد من الاتساق
      await _loadData();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ضبط رصيد المحفظة إلى EGP ${entered.toStringAsFixed(2)}')));
    } catch (e, st) {
      debugPrint('Error setting wallet amount: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _withdrawFromWallet() async {
    final text = _walletController.text.trim();
    final requested = double.tryParse(text.replaceAll(',', '')) ?? 0.0;

    setState(() => _loading = true);
    try {
      final dbHelper = DBHelper.instance;
      await dbHelper.ensureCardWalletTable();

      // canonical current wallet (ledger SUM)
      final latestWallet = await dbHelper.getLatestCardWalletAmount();
      final totalUntransferred = await _getUntransferredCardAmountSafe();
      final combinedAvailable = latestWallet + totalUntransferred;

      if (requested > combinedAvailable + 0.000001) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('الرصيد غير كافٍ. المتاح: EGP ${combinedAvailable.toStringAsFixed(2)}')),
          );
        }
        return;
      }

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : 'admin';

      double remaining = requested;

      // 1) withdraw from wallet first (as ledger delta)
      final withdrawFromWallet = (latestWallet >= remaining) ? remaining : latestWallet;
      if (withdrawFromWallet > 0.000001) {
        await dbHelper.changeCardWalletBy(-withdrawFromWallet, username, note: 'Withdraw from wallet (-${withdrawFromWallet.toStringAsFixed(2)})');
        remaining -= withdrawFromWallet;
      }

      // 2) if still remaining, try to consume untransferred card sales via helper
      if (remaining > 0.000001) {
        // transferUntransferredSalesAndWithdraw will mark sales as transferred and record wallet entries accordingly.
        // It may throw if not enough untransferred (shouldn't, because we checked combinedAvailable).
        await dbHelper.transferUntransferredSalesAndWithdraw(remaining, username, note: 'Withdraw from combined (admin) - consume untransferred ${remaining.toStringAsFixed(2)}');
        remaining = 0.0;
      }

      // optimistic local update: recompute wallet/untransferred after ops
      final afterWallet = await dbHelper.getLatestCardWalletAmount();
      final afterUntrans = await _getUntransferredCardAmountSafe();
      setState(() {
        _walletAmount = afterWallet;
        _cardReceived = afterUntrans;
        _cardTotalAvailable = _walletAmount + _cardReceived;
        _walletController.text = _walletAmount.toStringAsFixed(2);
      });

      await _loadData();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم سحب EGP ${requested.toStringAsFixed(2)}')));
    } catch (e, st) {
      debugPrint('Error withdrawing from wallet: $e\n$st');
      // rollback UI to canonical
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل السحب: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _overrideDrawer = false;

  Future<void> _saveStartingAmount_replace() async {
    final text = _drawerController.text.trim();
    final entered = double.tryParse(text.replaceAll(',', '')) ?? 0.0;

    setState(() => _loading = true);
    try {
      final dbHelper = DBHelper.instance;
      final db = await dbHelper.database;

      // حدود التاريخ (لتقييد التصفير لنطاق التواريخ إذا كان محددًا)
      final fromStr = _fromDate != null ? _dateFormat.format(_fromDate!) : null;
      final toStr = _toDate != null ? _dateFormat.format(_toDate!) : null;

      // نحسب القيم التقليدية للاحتياط
      final totals = await dbHelper.getDrawerTotals(fromDate: fromStr, toDate: toStr);
      final salesNetCash = (totals['sales_net_cash'] as num?)?.toDouble()
          ?? (totals['sales_net'] as num?)?.toDouble()
          ?? 0.0;

      double purchasePaidCash = 0.0;
      try {
        final rows = await db.rawQuery(
            "SELECT SUM(COALESCE(paid_amount,0)) AS total FROM purchase_receipts WHERE payment_type = 'cash'"
        );
        purchasePaidCash = (rows.isNotEmpty && rows.first['total'] != null)
            ? (rows.first['total'] as num).toDouble()
            : 0.0;
      } catch (e) {
        debugPrint('Failed to compute purchasePaidCash in _saveStartingAmount_replace: $e');
        purchasePaidCash = 0.0;
      }

      // إذا override مفعل: نرغب بأن يصبح صافي المبيعات = 0 فعليًا عن طريق تعليم المبيعات كـ "مسحوبة"
      final double desiredStarting = _overrideDrawer
          ? entered
          : (entered - (salesNetCash - purchasePaidCash));

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null)
          ? currentUser['username'] as String
          : 'admin';

      // نفعل إعادة التعيين داخل معاملة لضمان الاتساق
      await db.transaction((txn) async {
        // backup بسيط لجدول الدرج
        try {
          await txn.execute('CREATE TABLE IF NOT EXISTS cash_drawer_backup AS SELECT * FROM cash_drawer WHERE 0;');
          await txn.execute('INSERT INTO cash_drawer_backup SELECT * FROM cash_drawer;');
        } catch (e) {
          debugPrint('Could not create/copy cash_drawer_backup: $e');
        }

        // نحذف السجلات الحالية في الدرج لبدء "نظيف"
        await txn.delete('cash_drawer');

        // ---- إذا override مفعل، نملأ/ننشئ عمود drawer_withdrawn_amount ونصفر صافي المبيعات (بواسطة وسم السجلات) ---
        if (_overrideDrawer) {
          // تأكد من وجود العمود، وإلا أضفه
          try {
            final cols = await txn.rawQuery("PRAGMA table_info(sales);");
            final hasDrawerWithdrawn = cols.any((c) => (c['name'] as String) == 'drawer_withdrawn_amount');
            if (!hasDrawerWithdrawn) {
              await txn.execute("ALTER TABLE sales ADD COLUMN drawer_withdrawn_amount REAL NOT NULL DEFAULT 0;");
              // لو ALTER TABLE لم يدعم وضع قيم افتراضية، العمود سيأخذ القيمة 0 تلقائياً
            }

            // جهّز شرط التاريخ إن وجد
            String dateCondition = '';
            final List<Object?> args = <Object?>[];
            if (fromStr != null && toStr != null) {
              dateCondition = " AND date(date) BETWEEN ? AND ?";
              args.addAll([fromStr, toStr]);
            } else if (fromStr != null) {
              dateCondition = " AND date(date) >= ?";
              args.add(fromStr);
            } else if (toStr != null) {
              dateCondition = " AND date(date) <= ?";
              args.add(toStr);
            }

            // حدّث كل مبيعات النقد لتُعامل كأنها "مسحوبة" (بذلك يكون صافي المبيعات النقدي = 0 عند الاستعلامات التي تطرح drawer_withdrawn_amount).
            await txn.rawUpdate('''
            UPDATE sales
            SET drawer_withdrawn_amount = (COALESCE(paid_amount,0) - COALESCE(change_amount,0))
            WHERE payment_method = 'cash'
              $dateCondition
          ''', args);
          } catch (e) {
            debugPrint('Failed to mark sales as withdrawn for override: $e');
            // لا نفشل المعاملة كاملة بسبب فشل التصفير، لكن نعلم في السجل
          }
        }

        // إدخال صف البداية الجديد في cash_drawer
        final now = DateTime.now().toIso8601String();
        await txn.insert('cash_drawer', {
          'amount': desiredStarting,
          'updated_by': username,
          'note': _overrideDrawer
              ? 'Override: set starting amount directly to ${desiredStarting.toStringAsFixed(2)} (sales_net marked withdrawn)'
              : 'Reset starting amount to ${desiredStarting.toStringAsFixed(2)} to force drawer display EGP ${entered.toStringAsFixed(2)} (full reset)',
          'created_at': now,
        });
      });

      // حدث واجهة المستخدم فوراً
      if (mounted) {
        setState(() {
          _drawerController.text = entered.toStringAsFixed(2);
          _startingAmount = desiredStarting;
          _currentDrawer = entered;
          if (_overrideDrawer) {
            _salesNet = 0.0; // عرض فوري أن صافي المبيعات أصبح صفر
          }
        });
      }

      // أعِد تحميل البيانات canonical للتأكد من الاتساق مع DB
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إعادة تعيين الدرج وبداية جديدة بقيمة EGP ${entered.toStringAsFixed(2)}')),
        );
      }
    } catch (e, st) {
      debugPrint('Error replacing drawer amount (full reset): $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء إعادة التعيين: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      await _loadData();
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      await _loadData();
    }
  }

  void _clearDateFilters() async {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    await _loadData();
  }

  Widget _buildSummaryRow(String label, double value, {TextStyle? style}) {
    final formatted = _formatMoney(value.abs());
    final sign = value < 0 ? '-' : '';
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white);
    final valueStyle = effectiveStyle?.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white) ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label, style: effectiveStyle,
            ),
            Text('$sign$formatted', style: valueStyle),
          ],
        ),
      ),
    );
  }

  Widget _desktopLayout(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.clamp(800.0, 1400.0);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
                flex: 3,
                child: Card(
                  color: AppColorsDark.bgCardColor,
                  margin: const EdgeInsets.only(right: 12.0, top: 8.0, bottom: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                                'تعيين المبلغ المبدئي في الدرج',
                                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                                    color: Colors.white
                                )
                            ),
                          ),
                          const SizedBox(height: 20),
                          CustomFormField(
                            controller: _drawerController,
                            hint: 'EGP المبلغ في الدرج الآن',
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 20),
                          CustomButton(
                                text: 'حفظ القيمه للدرج',
                                onPressed: _saveStartingAmount_replace,
                                infinity: true,
                          ),
                          SizedBox(height: 20,),
                          Divider(height: 30,color: AppColorsDark.mainColor,),
                          Center(
                            child: Text(
                                'تعيين/تعديل رصيد المحفظة الإلكترونية',
                                style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)
                            ),
                          ),
                          const SizedBox(height: 12),
                          CustomFormField(
                            controller: _walletController,
                            hint: 'EGP رصيد المحفظة',
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                          ),
                          const SizedBox(height: 20),
                              CustomButton(
                                text: 'حفظ القيمه للمحفظة',
                                onPressed: _addToWallet,
                                infinity: true,
                                color: AppColorsDark.mainColor.withOpacity(0.7),
                              ),
                          SizedBox(height: 20,),
                          Divider(height: 30,color: AppColorsDark.mainColor,),
                          Center(
                            child: Text(
                                'تصفية حسب التاريخ',
                                style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Colors.white)
                            ),
                          ),
                          const SizedBox(height: 10),
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('من تاريخ', style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white)),
                                    SizedBox(height: 15,),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: AppColorsDark.bgColor,
                                      ),
                                      onPressed: _pickFromDate,
                                      child: Text(
                                        _fromDate == null ? 'اختر' : _dateFormat.format(_fromDate!),
                                        style: TextStyle(
                                            color: Colors.white
                                        ),
                                      ),
                                    )
                                  ]
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('إلى تاريخ', style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white)),
                                    SizedBox(height: 15,),
                                    TextButton(
                                        style: TextButton.styleFrom(
                                          backgroundColor: AppColorsDark.bgColor,
                                        ),
                                        onPressed: _pickToDate,
                                        child: Text(
                                          _toDate == null ? 'اختر' : _dateFormat.format(_toDate!),
                                          style: TextStyle(
                                              color: Colors.white
                                          ),
                                        )
                                    ),
                                  ]),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20,),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColorsDark.bgColor,
                                ),
                                onPressed: _clearDateFilters,
                                icon: const Icon(Icons.clear,color: Colors.white70,),
                                label:Text('مسح الفلاتر',style: TextStyle(color: Colors.white),)
                            ),
                          ),
                          Divider(height: 30,color: AppColorsDark.mainColor,),
                          Center(
                            child: Text(
                                'ملخص سريع',
                                style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)),
                          ),
                          const SizedBox(height: 10),
                          _buildSummaryRow('المبلغ المتواجد في الدرج', _currentDrawer),
                          const SizedBox(height: 10),
                          _buildSummaryRow('صافي مبيعات نقدي', _salesNet),
                          const SizedBox(height: 10),
                          _buildSummaryRow('صافي مبيعات المحفظة الإلكترونية', _cardNetSales),
                          const SizedBox(height: 10),
                          _buildSummaryRow('تعديلات/مرتجعات', _returnsDelta),
                          const SizedBox(height: 10),
                          _buildSummaryRow('مدفوعات مشتريات (نقدي)', _purchasePaidCash),
                          const SizedBox(height: 8),
                          _buildSummaryRow("المدفوع (مشتريات آجلة)", _purchasePaid),
                          const SizedBox(height: 10),
                          _buildSummaryRow("المتبقي (مشتريات آجلة)", _purchaseDue),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                )),
            Flexible(
              flex: 6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                    child: Row(
                      children: [
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
                                      child: Text(
                                          'المبلغ في الدرج الآن',
                                          style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                              "جنيه",
                                              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                          SizedBox(width: 10,),
                                          Text(
                                              _formatWithSign(_currentDrawer),
                                              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: (){
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context)=> receiptsScreen(initialFilter: 'card',))
                              );
                            },
                            child: SizedBox(
                              height: 200,
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.bgCardColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Center(
                                        child: Text(
                                            'المبلغ في المحفظه الالكترونيه',
                                            style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                    "جنيه",
                                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                                SizedBox(width: 10,),
                                                Text(
                                                    _formatMoney(_cardTotalAvailable),
                                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 8),
                                      // ---------- زر التحويل ----------
                                      if(_cardTotalAvailable > 0.0)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: _showTransferDialog,
                                            icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.white),
                                            label: const Text('تحويل إلى الدرج', style: TextStyle(color: Colors.white)),
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: InkWell(
                              onTap: (){
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(builder:(context)=>CreditsScreen() )
                                );
                              },
                              child: SizedBox(
                                height: 200,
                                child: Card(
                                  elevation: 3,
                                  color: AppColorsDark.mainColor.withOpacity(0.08),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Text(
                                              'المبلغ المستحق',
                                              style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                  "جنيه",
                                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                              SizedBox(width: 10,),
                                              Text(
                                                  _formatMoney(_creditOutstanding),
                                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold,color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            ))],
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                      color: AppColorsDark.bgCardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SingleChildScrollView(
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(child: Text('التقارير المفصلة', style: Theme.of(context).textTheme.displaySmall!.copyWith(color: Colors.white))),
                                const SizedBox(height: 12),
                                // place holders: يمكنك هنا وضع شارت/قوائم مفصّلة
                                ListTile(
                                  leading: const Icon(Icons.receipt_long,color: Colors.white70,),
                                  title: const Text(
                                    'سندات الشراء - مدفوعة',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                    ),
                                  ),
                                  onTap: () async {
                                    final paidReceipts = await DBHelper.instance.getPaidPurchaseReceipts();
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPaidPurchasesScreen()));
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.credit_card,color: Colors.white70,),
                                  title: const Text(
                                    'سندات الشراء - آجل',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,

                                    ),
                                  ),
                                  onTap: () async {
                                    final changed = await Navigator.of(context).push<bool?>(
                                      MaterialPageRoute(builder: (_) => const AdminLaterPurchasesScreen()),
                                    );
                                    if (changed == true) {
                                      await _loadData();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileLayout() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تعيين المبلغ المبدئي في الدرج', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _drawerController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'المبلغ في الدرج',
                prefixText: 'EGP ',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _saveStartingAmount_replace, child: const Text('حفظ'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _loadData, child: const Text('تحديث'))),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Card(
                  color: Theme.of(context).cardColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                    child: Column(
                      children: [
                        Text('المبلغ في الدرج الآن', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Text('EGP ' + _formatMoney(_currentDrawer), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text('المعادلة: المبدئي + مبيعات نقدية - مدفوعات مشتريات (نقدي)', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Text(' مدفوعات مشتريات: ${_formatMoney(_purchasePaidCash)}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).cardColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                    child: Column(
                      children: [
                        Text('المبلغ المتاح للتحويل (Card + Wallet)', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Text('EGP ' + _formatMoney(_cardTotalAvailable), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text('(${_formatMoney(_cardReceived)} غير محوّل من المبيعات + ${_formatMoney(_walletAmount)} رصيد المحفظة)', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _showTransferDialog,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('تحويل إلى الدرج'),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  color: AppColorsDark.mainColor.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                    child: Column(
                      children: [
                        Text('المبلغ المستحق (عملاء)', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Text('EGP ' + _formatMoney(_creditOutstanding), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text('إجمالي مستحقات الفواتير الآجلة (الفرق بين المجموع والمدفوع)', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).cardColor,
                  child: ListTile(
                    title: const Text('سندات شراء - آجل'),
                    trailing: Text(_formatMoney(_purchaseReceiptsOutstanding), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool?>(
                        MaterialPageRoute(builder: (_) => const AdminLaterPurchasesScreen()),
                      );
                      if (changed == true) {
                        await _loadData();
                      }
                    },
                  ),
                ),

              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).cardColor,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    _buildSummaryRow('المبلغ المبدئي', _startingAmount),
                    _buildSummaryRow('صافي مبيعات نقدي (مدفوع - بقية)', _salesNet),
                    _buildSummaryRow('تعديلات/مرتجعات)', _returnsDelta),
                    _buildSummaryRow('مدفوعات مشتريات (نقدي)',_purchasePaidCash),
                    _buildSummaryRow('المبلغ المستحق (عملاء)', _creditOutstanding),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
        iconTheme: IconThemeData(
            color: Colors.white70
        ),
        title: const Text(
          'الدرج والتقارير',
          style: TextStyle(
              fontSize: 27,
              color: Colors.white
          ),
        ),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          // desktop if wide enough
          if (constraints.maxWidth >= 900) {
            return _desktopLayout(constraints);
          } else {
            return _mobileLayout();
          }
        },
      ),
    );
  }


  Future<void> _showTransferDialog() async {
    final dbHelper = DBHelper.instance;

    final totalUntransferred = await _getUntransferredCardAmountSafe();
    double walletLatest = 0.0;
    try {
      await dbHelper.ensureCardWalletTable();
      walletLatest = await dbHelper.getLatestCardWalletAmount();
    } catch (e) {
      debugPrint('Could not read wallet amount for dialog: $e');
      walletLatest = 0.0;
    }

    final combined = (totalUntransferred + walletLatest);
    final controller = TextEditingController(text: combined.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: Center(
            child: Text(
              'تحويل من المحفظة الإلكترونية إلى الدرج',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white),
            ),
          ),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'المبلغ المتاح للتحويل: EGP ${combined.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                CustomFormField(
                  controller: controller,
                  hint: 'المبلغ للتحويل (أدخل قيمة أو اضغط نقل الكل)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgColor,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _transferCardToDrawer(amount: combined);
              },
              child: const Text(
                'نقل الكل',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgColor,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(color: Colors.white),
              ),
            ),
            CustomButton(
              text: 'نقل',
              onPressed: () {
                final text = controller.text.trim().replaceAll(',', '');
                double amt = double.tryParse(text) ?? 0.0;
                if (amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغ صالح للتحويل')));
                  return;
                }
                if (amt > combined) {
                  amt = combined;
                }
                Navigator.of(ctx).pop();
                _transferCardToDrawer(amount: amt);
              },
              infinity: false,
            ),
          ],
        );
      },
    );
  }

  Future<void> _transferCardToDrawer({required double amount}) async {
    setState(() => _loading = true);
    final dbHelper = DBHelper.instance;
    final db = await dbHelper.database;

    try {
      final totalUntransferred = await _getUntransferredCardAmountSafe();
      final latestWallet = await dbHelper.getLatestCardWalletAmount();
      double combinedAvailable = totalUntransferred + latestWallet;
      double transferAmount = amount;
      if (transferAmount > combinedAvailable) transferAmount = combinedAvailable;
      if (transferAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مبلغ قابل للتحويل')));
        return;
      }

      final cols = await db.rawQuery("PRAGMA table_info(sales);");
      final hasTransferredAmount = cols.any((c) => (c['name'] as String) == 'card_transferred_amount');
      if (!hasTransferredAmount) {
        await db.execute("ALTER TABLE sales ADD COLUMN card_transferred_amount REAL NOT NULL DEFAULT 0;");
      }
      final hasCardTransferredFlag = cols.any((c) => (c['name'] as String) == 'card_transferred');
      if (!hasCardTransferredFlag) {
        await db.execute("ALTER TABLE sales ADD COLUMN card_transferred INTEGER NOT NULL DEFAULT 0;");
        await db.update('sales', {'card_transferred': 0});
      }

      final latestStarting = await dbHelper.getLatestDrawerStartingAmount();
      final newStarting = latestStarting + transferAmount;

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : 'admin';

      await db.transaction((txn) async {
        double remaining = transferAmount;

        final rows = await txn.rawQuery('''
        SELECT id,
               COALESCE(paid_amount,0) - COALESCE(change_amount,0) AS net_paid,
               COALESCE(card_transferred_amount,0) AS transferred_amount
        FROM sales
        WHERE payment_method = ?
          AND (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) > COALESCE(card_transferred_amount,0)
        ORDER BY date ASC
      ''', ['card']);

        for (final r in rows) {
          if (remaining <= 0) break;

          final int saleId = (r['id'] as num).toInt();
          final double netPaid = (r['net_paid'] as num).toDouble();
          final double transferred = (r['transferred_amount'] as num).toDouble();
          final double available = netPaid - transferred;
          if (available <= 0) continue;

          if (available <= remaining + 0.00001) {
            final newTransferred = netPaid;
            await txn.update('sales', {
              'card_transferred_amount': newTransferred,
              'card_transferred': 1,
            }, where: 'id = ?', whereArgs: [saleId]);
            remaining -= available;
          } else {
            final newTransferred = transferred + remaining;
            await txn.update('sales', {
              'card_transferred_amount': newTransferred,
            }, where: 'id = ?', whereArgs: [saleId]);
            remaining = 0.0;
          }
        }

        if (remaining > 0.00001) {
          final walletRows = await txn.rawQuery('SELECT SUM(COALESCE(amount,0)) as wallet_sum FROM card_wallet');
          double walletLatestSum = 0.0;
          if (walletRows.isNotEmpty && walletRows.first['wallet_sum'] != null) {
            walletLatestSum = (walletRows.first['wallet_sum'] as num).toDouble();
          }

          double consumeFromWallet = remaining;
          if (consumeFromWallet > walletLatestSum) consumeFromWallet = walletLatestSum;

          if (consumeFromWallet > 0.00001) {
            final now = DateTime.now().toIso8601String();
            await txn.insert('card_wallet', {
              'amount': -consumeFromWallet,
              'updated_by': username,
              'note': 'Deduct for transfer to drawer (-${consumeFromWallet.toStringAsFixed(2)})',
              'created_at': now,
            });
            remaining -= consumeFromWallet;
          }
        }

        final now = DateTime.now().toIso8601String();
        await txn.insert('cash_drawer', {
          'amount': newStarting,
          'updated_by': username,
          'note': 'Transfer from card to drawer (+${transferAmount.toStringAsFixed(2)})',
          'created_at': now,
        });
      });

      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إضافة EGP ${transferAmount.toStringAsFixed(2)} إلى الدرج')));
    } catch (e, st) {
      debugPrint('Error transferring card to drawer: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحويل: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }}

