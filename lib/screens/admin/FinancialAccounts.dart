// admin_cash_drawer_page_network.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:http/http.dart' as http;
import '../../services/Api/Admin/financle.dart';
import '../../utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';

// عدّل المسار حسب مكان ملف الخدمة عندك

class AdminCashDrawerPage extends StatefulWidget {
  const AdminCashDrawerPage({Key? key}) : super(key: key);

  @override
  State<AdminCashDrawerPage> createState() => _AdminCashDrawerPageState();
}

class _AdminCashDrawerPageState extends State<AdminCashDrawerPage> {
  // Controllers منفصلة كما طلبت
  final TextEditingController _startingController = TextEditingController(); // لتعيين المبلغ المبدئي في الدرج
  final TextEditingController _maxLimitController = TextEditingController(); // لوضع الحد الاقصي لبدايه الدرج بعد تقفيل الشيفت
  final TextEditingController _walletController = TextEditingController(); // رصيد المحفظة

  final NumberFormat _moneyFmt = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  final NumberFormat _moneyFmtNoDecimal = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  bool _loading = true;

  double _startingAmount = 0.0;
  double _maxLimit = 0.0;
  double _cashInWallet = 0.0;
  double _startingInWallet = 0.0;
  double _totalInDrawer = 0.0;
  double _salesNet = 0.0;
  double _purchasePaidCash = 0.0;
  double _creditOutstanding = 0.0;

  // service الشبكة — عدّل baseUrl إلى عنوان API الخاص بك
  final InsertFinancialAccountService _service = InsertFinancialAccountService();

  // --- إضافات لعرض تقفيلات الشيفت لكل كاشير ---
  final String _closeShiftUrl = 'https://nabawisolution.com/get_close_shieft.php';
  List<CloseShift> _shifts = [];
  bool _loadingShifts = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadShifts(); // جلب تقفيلات الشيفت للتاريخ الحالي افتراضياً
  }

  @override
  void dispose() {
    _startingController.dispose();
    _maxLimitController.dispose();
    _walletController.dispose();
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

  // تحميل اخر سجل من السيرفر (latest record)
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final list = await _service.getLatest(limit: 1);
      if (list.isNotEmpty) {
        final rec = list.first;
        setState(() {
          _startingAmount = rec.startingAmount;
          _maxLimit = rec.maxLimit;
          _cashInWallet = rec.cashInWallet;
          _startingInWallet = rec.cashInWallet;
          // قد تكون القيمة من السيرفر null => نتعامل معها ونعرض 0.0 في الحالة دي
          _totalInDrawer = rec.totalInDrawer ?? 0.0;

          _startingController.text = _startingAmount.toStringAsFixed(2);
          _maxLimitController.text = _maxLimit.toStringAsFixed(2);
          _walletController.text = _cashInWallet.toStringAsFixed(2);
        });
      } else {
        setState(() {
          _startingAmount = 0.0;
          _maxLimit = 0.0;
          _cashInWallet = 0.0;
          _totalInDrawer = 0.0;

          _startingController.text = '0.00';
          _maxLimitController.text = '0.00';
          _walletController.text = '0.00';
        });
      }
    } catch (e, st) {
      debugPrint('Failed to load financial accounts from API: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل تحميل البيانات من السيرفر: $e',
              textAlign: TextAlign.right,
            )
        )
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- دوال الحفظ كما في كودك الأصلي ----------
  Future<void> _saveStartingAmount_replace() async {
    final text = _startingController.text.trim().replaceAll(',', '');
    final entered = double.tryParse(text) ?? 0.0;

    setState(() => _loading = true);
    try {
      final payload = FinancialAccount(
        startingAmount: entered,
        maxLimit: _maxLimit,
        cashInWallet: _cashInWallet,
      );

      final inserted = await _service.insert(payload);

      setState(() {
        _startingAmount = inserted.startingAmount;
        _maxLimit = inserted.maxLimit;
        _cashInWallet = inserted.cashInWallet;
        _totalInDrawer = inserted.totalInDrawer ?? 0.0;

        _startingController.text = _startingAmount.toStringAsFixed(2);
        _maxLimitController.text = _maxLimit.toStringAsFixed(2);
        _walletController.text = _cashInWallet.toStringAsFixed(2);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                'تم حفظ مبلغ البداية بنجاح',
              textAlign: TextAlign.right,
            )));
      }
    } on ValidationException catch (ve) {
      final msg = ve.errors.join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          msg,
        textAlign: TextAlign.right,
      )
      )
      );
    } on ApiException catch (ae) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'API error: ${ae.message}',
          textAlign: TextAlign.right,

      )
      )
      );
    } catch (e) {
      debugPrint('Error saving starting amount via API: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'خطأ أثناء الحفظ: $e',
        textAlign: TextAlign.right,

      )
      )
      );
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
        cashInWallet: _cashInWallet,
      );

      final inserted = await _service.insert(payload);

      setState(() {
        _startingAmount = inserted.startingAmount;
        _maxLimit = inserted.maxLimit;
        _cashInWallet = inserted.cashInWallet;
        _totalInDrawer = inserted.totalInDrawer ?? 0.0;

        _startingController.text = _startingAmount.toStringAsFixed(2);
        _maxLimitController.text = _maxLimit.toStringAsFixed(2);
        _walletController.text = _cashInWallet.toStringAsFixed(2);
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'تم حفظ الحد الأقصى بنجاح',
        textAlign: TextAlign.right,

      )
      )
      );
    } on ValidationException catch (ve) {
      final msg = ve.errors.join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          msg,
        textAlign: TextAlign.right,
      )));
    } on ApiException catch (ae) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'API error: ${ae.message}',
        textAlign: TextAlign.right,

      )));
    } catch (e) {
      debugPrint('Error saving max limit via API: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'خطأ أثناء الحفظ: $e',
        textAlign: TextAlign.right,

      )));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToWallet() async {
    final text = _walletController.text.trim().replaceAll(',', '');
    final entered = double.tryParse(text) ?? 0.0;
    if (entered < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'أدخل مبلغًا صالحًا (0 أو أكبر)',
        textAlign: TextAlign.right,

      )));
      return;
    }

    setState(() => _loading = true);
    try {
      final payload = FinancialAccount(
        startingAmount: _startingAmount,
        maxLimit: _maxLimit,
        cashInWallet: entered,
      );

      final inserted = await _service.insert(payload);

      setState(() {
        _startingAmount = inserted.startingAmount;
        _maxLimit = inserted.maxLimit;
        _cashInWallet = inserted.cashInWallet;
        _totalInDrawer = inserted.totalInDrawer ?? 0.0;

        _startingController.text = _startingAmount.toStringAsFixed(2);
        _walletController.text = _cashInWallet.toStringAsFixed(2);
        _maxLimitController.text = _maxLimit.toStringAsFixed(2);
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'تم ضبط رصيد المحفظة إلى EGP ${entered.toStringAsFixed(2)}',
            textAlign: TextAlign.right,

          )));
    } on ValidationException catch (ve) {
      final msg = ve.errors.join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg,              textAlign: TextAlign.right,
      )));
    } on ApiException catch (ae) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API error: ${ae.message}',              textAlign: TextAlign.right,
      )));
    } catch (e) {
      debugPrint('Error updating wallet via API: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء تحديث المحفظة: $e',              textAlign: TextAlign.right,
      )));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _transferCardToDrawer({required double amount}) async {
    setState(() => _loading = true);
    try {
      double transferAmount = amount;
      if (transferAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مبلغ قابل للتحويل',              textAlign: TextAlign.right,
        )));
        setState(() => _loading = false);
        return;
      }

      if (transferAmount > _cashInWallet) transferAmount = _cashInWallet;

      final newWallet = _cashInWallet - transferAmount;

      final payload = FinancialAccount(
        startingAmount: _startingAmount,
        maxLimit: _maxLimit,
        cashInWallet: newWallet,
      );

      final inserted = await _service.insert(payload);

      setState(() {
        _cashInWallet = inserted.cashInWallet;
        _totalInDrawer = inserted.totalInDrawer ?? 0.0;
        _walletController.text = _cashInWallet.toStringAsFixed(2);
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إضافة EGP ${transferAmount.toStringAsFixed(2)} إلى الدرج',
        textAlign: TextAlign.right,
      )));
    } on ValidationException catch (ve) {
      final msg = ve.errors.join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg,
        textAlign: TextAlign.right,
      )));
    } on ApiException catch (ae) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API error: ${ae.message}',
        textAlign: TextAlign.right,
      )));
    } catch (e) {
      debugPrint('Error transferring via API: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحويل: $e',
        textAlign: TextAlign.right,
      )));
      await _loadData();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // ------------------ واجهة المستخدم ------------------
  Widget _buildSummaryRow(String label, double value, {TextStyle? style}) {
    final formatted = _formatMoney(value.abs());
    final sign = value < 0 ? '-' : '';
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium!.copyWith(color: Colors.white);
    final valueStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: effectiveStyle),
            Text('$sign$formatted', style: valueStyle),
          ],
        ),
      ),
    );
  }

  // ------------------ دوال جديدة: تحميل تقفيلات الشيفت ------------------
  Future<void> _loadShifts({DateTime? date, bool tryWithoutDateIfEmpty = false}) async {
    final d = date ?? _selectedDate;
    final dateStr = _dateFormat.format(d);

    if (!mounted) return;
    setState(() {
      _loadingShifts = true;
    });

    try {
      final baseUri = Uri.parse(_closeShiftUrl);

      // نرسل table افتراضي
      Uri uri = baseUri.replace(queryParameters: {
        'date': dateStr,
        'table': 'close_shieft',
      });

      final headers = {
        'User-Agent': 'Mozilla/5.0 (Flutter)',
        'Accept': 'application/json',
      };

      debugPrint('Trying GET $uri');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      debugPrint('-> status ${resp.statusCode}');
      debugPrint('-> full response body:\n${resp.body}');

      if (resp.statusCode != 200) {
        String serverMsg = resp.body;
        try {
          final parsed = json.decode(resp.body);
          if (parsed is Map && parsed.containsKey('error')) serverMsg = parsed['error'].toString();
        } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ من السيرفر ${resp.statusCode}: ${serverMsg.length>200?serverMsg.substring(0,200)+'...':serverMsg}',
          textAlign: TextAlign.right,
        )));
        if (mounted) setState(() => _shifts = []);
        return;
      }

      // معالجة الجسم كما سابق
      await _processShiftsResponse(resp.body, d);

      // **ملاحظة**: لم نعد نجرب تلقائيًا بدون تاريخ عند عدم وجود صفوف.
      // هذا السلوك يضمن أنّه لو المستخدم اختار تاريخ معين ولم يتم العثور على بيانات
      // لن يتم عرض "كل التقفيلات" بدون إذن المستخدم.
    } catch (e, st) {
      debugPrint('Failed to load close shifts: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل تقفيلات الشيفت: $e',
          textAlign: TextAlign.right,
        )));
        setState(() => _shifts = []);
      }
    } finally {
      if (mounted) setState(() => _loadingShifts = false);
    }
  }
  double _purchasePaidOnCredit = 0.0;       // المدفوع لمشتريات آجلة (دفعات على الائتمان)



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
          final possible = decoded.values.firstWhere((v) => v is List, orElse: () => null);
          if (possible is List) listData = possible;
        }
      } else {
        debugPrint('Unexpected JSON shape: ${decoded.runtimeType}');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('استجابة غير متوقعة من السيرفر. راجع اللوغ.',
          textAlign: TextAlign.right,
        )));
        if (mounted) setState(() => _shifts = []);
        return;
      }
    } catch (e) {
      debugPrint('JSON decode failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فك JSON: $e',
          textAlign: TextAlign.right,

        )));
        setState(() => _shifts = []);
      }
      return;
    }

    // بناء الـ model من listData + حساب المجاميع المطلوبة
    final shifts = <CloseShift>[];
    double totalDrawerSum = 0.0;
    double totalWalletSum = 0.0;
    double totalCreditSum = 0.0;
    double totalSalesCash = 0.0;
    double totalPurchasesPaidCash = 0.0;

    // المجاميع الجديدة للمشتريات الآجلة
    double totalPurchasesPaidOnCredit = 0.0;

    for (final e in listData) {
      if (e is Map) {
        final name = _pickStringFromMap(e, ['cashier_name', 'cashier', 'name', 'username', 'user']);
        final drawer = _pickDoubleFromMap(e, [
          'total_in_drawer', 'total_in_cash', 'drawer_total', 'total_drawer', 'total_inbox', 'in_drawer'
        ]) ?? 0.0;
        final wallet = _pickDoubleFromMap(e, [
          'total_in_wallet', 'wallet_total', 'total_wallet', 'cash_in_wallet', 'in_wallet'
        ]) ?? 0.0;

        // مبيعات نقدي / محفظة
        final salesCash = _pickDoubleFromMap(e, [
          'profit_value_cash', 'profit_cash', 'sales_cash', 'cash_sales', 'net_cash', 'profit_value'
        ]) ?? 0.0;


        // مشتريات مدفوعة نقداً (موجود سابقاً)
        final purchasesPaidCash = _pickDoubleFromMap(e, [
          'purchases_paid', 'purchases_paid_cash', 'purchases_cash_paid'
        ]) ?? 0.0;

        // ---------- استخراج المدفوع لمشتريات آجلة (محاولات متعددة) ----------
        double purchasesPaidOnCredit = 0.0;

        // 1) قائمة مفاتيح مرشحة (أعطى الأولوية للمفاتيح التي تحتوي كلمة credit)
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

        // 2) إذا لم نجد شيء، حاول حسابه من (purchases_paid_total - purchases_paid_cash) إن توفرا
        if (purchasesPaidOnCredit == 0.0) {
          final totalPaidPossible = _pickDoubleFromMap(e, ['purchases_paid_total', 'purchases_total_paid', 'purchases_paid', 'purchases_total']);
          final paidCashPossible = _pickDoubleFromMap(e, ['purchases_paid_cash', 'purchases_cash_paid', 'purchases_cash']);
          if (totalPaidPossible != null && paidCashPossible != null) {
            purchasesPaidOnCredit = totalPaidPossible - paidCashPossible;
          }
        }

        // 3) بحث ديناميكي في المفاتيح: لو المفتاح يحتوي كلمات credit + paid أو purchases + credit
        if (purchasesPaidOnCredit == 0.0) {
          for (final entry in e.entries) {
            final key = entry.key.toString().toLowerCase();
            if ((key.contains('credit') && (key.contains('paid') || key.contains('payment'))) ||
                ((key.contains('purchase') || key.contains('purchas') || key.contains('purchases')) && key.contains('credit'))) {
              // حاول تحويل القيمة
              final val = entry.value;
              double? numVal;
              if (val is num) numVal = val.toDouble();
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

        // 4) ضمان عدم أن تكون سالبة
        if (purchasesPaidOnCredit.isNegative) purchasesPaidOnCredit = 0.0;

        // فواتير آجلة / مستحقات عامة
        final credit = _pickDoubleFromMap(e, [
          'cash_with_credit', 'credit_outstanding', 'total_credit', 'due_amount', 'outstanding', 'credit_value', 'credit'
        ]) ?? 0.0;

        shifts.add(CloseShift(
          cashierName: name ?? 'غير معروف',
          totalInDrawer: drawer,
          totalInWallet: wallet,
          raw: Map<String, dynamic>.from(e),
        ));

        totalDrawerSum += drawer;
        totalWalletSum += wallet;
        totalCreditSum += credit;
        totalSalesCash += salesCash;
        totalPurchasesPaidCash += purchasesPaidCash;

        // مجمّع المشتريات الآجلة
        totalPurchasesPaidOnCredit += purchasesPaidOnCredit;
      }
    }

    if (mounted) {
      setState(() {
        _shifts = shifts;
        _selectedDate = d;

        // القيم المجمعة للعرض في واجهة "ملخص سريع"
        _totalInDrawer = totalDrawerSum;
        _cashInWallet = totalWalletSum;
        _creditOutstanding = totalCreditSum;

        // قيم أخرى ملخصة
        _salesNet = totalSalesCash;
        _purchasePaidCash = totalPurchasesPaidCash;

        // **المتغيران الجدد**
        _purchasePaidOnCredit = totalPurchasesPaidOnCredit;

        // تحديث النص في حقول التحرير إن رغبت
        _walletController.text = _startingInWallet.toString();
      });
    }

    // تشخيص: لو وجدنا بيانات لكن الحقول فارغة، نظهر أول عنصر للوغ
    if (shifts.isEmpty && listData.isNotEmpty) {
      debugPrint('listData has entries but parser produced 0 shifts. First entry keys:');
      final first = listData.first;
      if (first is Map) {
        debugPrint(first.keys.toList().join(', '));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الاستجابة تحتوي عناصر لكن المفاتيح غير متوقعة — راجع اللوغ (keys)',
            textAlign: TextAlign.right,
          )));
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

    // قائمة الحقول المراد عرضها مع تسميات عربية مرتبة
    final List<List<String>> fields = [
      ['profit_value_cash', 'صافي مبيعات نقدي'],
      ['profit_value_wallet', 'صافي مبيعات محفظه'],
      ['cash_received', 'المستلم من خلال نقدًا'],
      ['wallet_received', 'المستلم من خلال محفظة'],
      ['deposit_from_cash_to_wallet', 'ايداع الي المحفظة'],
      ['deposit_from_wallet_to_cash', 'سحب من المحفظة'],
      ['purchases_paid', 'مشتريات مدفوعه'],
      ['purchases_credit', 'مشتريات الاجله'],
      ['cash_with_credit', 'الفواتير الاجله'],
      ['start_time', 'بداية الشيفت'],
      ['end_time', 'نهاية الشيفت'],
      ['total_in_drawer', 'الاجمالي في الدرج'],
      ['total_in_wallet', 'الاجمالي في المحفظه'],
    ];

    Widget buildRow(String label, String value, {bool isNumber = false}) {
      final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: label == "الاجمالي في الدرج" ? Colors.green : label == "الاجمالي في المحفظه" ? Colors.blueAccent : Colors.white70,
          fontSize: 14
      );
      final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: label == "الاجمالي في الدرج" ? Colors.green : label == "الاجمالي في المحفظه" ? Colors.blueAccent : Colors.white70,
          fontWeight: label == "الاجمالي في الدرج" ? FontWeight.bold: label == "الاجمالي في المحفظه" ? FontWeight.bold :FontWeight.normal,
          fontSize: label == "الاجمالي في الدرج" ? 15: label == "الاجمالي في المحفظه" ? 15 :13,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Text(
                  label,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                )
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(value, style: valueStyle, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }

    // Helper to extract string or number from raw map
    String _valueForKey(String key) {
      final raw = s.raw ?? {};
      if (raw.containsKey(key) && raw[key] != null) {
        final v = raw[key];

        if (v is num) return _formatMoney(v.toDouble());

        if (v is String) {
          // حاول تحويل النص إلى رقم أولاً
          final cleaned = v.replaceAll(',', '');
          final asNum = double.tryParse(cleaned);
          if (asNum != null) return _formatMoney(asNum);

          // حاول تحويله إلى DateTime بعدة أساليب
          DateTime? dt;
          // 1) ISO / full datetime
          try {
            dt = DateTime.parse(v);
          } catch (_) {
            dt = null;
          }

          // 2) محاولات لقراءة time-only بصيغ شائعة
          if (dt == null) {
            try {
              dt = DateFormat('HH:mm:ss').parseStrict(v);
            } catch (_) {
              try {
                dt = DateFormat('HH:mm').parseStrict(v);
              } catch (_) {
                dt = null;
              }
            }
          }

          if (dt != null) {
            // لو المطلوب هو بداية/نهاية الشيفت، نعرض الوقت فقط بصيغة 12 ساعة مع AM/PM
            if (key == 'start_time' || key == 'end_time') {
              // ملاحظة: DateFormat('hh:mm a') يعطي AM/PM باللغة الافتراضية.
              // لو تريد AM/PM بالعربي استعمل: DateFormat('hh:mm a', 'ar')
              return DateFormat('hh:mm a').format(dt);
            } else {
              // الحقول الأخرى نظهر تاريخ + وقت كما سابق
              return DateFormat('yyyy-MM-dd HH:mm').format(dt);
            }
          }

          // إن لم نتمكن من التحويل — نعيد النص كما هو
          return v;
        }
      }
      return '-';
    }

    return Card(
      color: AppColorsDark.bgCardColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // عنوان (اسم الكاشير) — نستخدم القيمة المرسلة أو الاسم الموجود في النموذج
              Text(
                s.cashierName.isNotEmpty ? s.cashierName : (_pickStringFromMap(s.raw ?? {}, ['cashier_name','cashier','name','username','user']) ?? 'غير معروف'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // عرض الحقول الأساسية (قائمة مرتبة)
              Column(
                children: fields.map((pair) {
                  final key = pair[0];
                  final label = pair[1];
                  final value = _valueForKey(key);
                  return buildRow(label, value);
                }).toList(),
              ),

              const SizedBox(height: 8),
            ],
          ),
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
                  style: const TextStyle(color: Colors.white70,fontSize: 17),
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
                      child: const Text('اليوم السابق',style: TextStyle(color: AppColorsDark.mainColor),),
                      style: OutlinedButton.styleFrom(
                        side:BorderSide(color: AppColorsDark.bgCardColor, width: 2), // سمك وحدود الزر
                        foregroundColor: AppColorsDark.mainColor, // لون النص والأيقونات
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(width: 20,),
                    OutlinedButton(
                      onPressed: () => _loadShifts(date: _selectedDate.add(const Duration(days: 1))),
                      child: const Text('اليوم التالي',style: TextStyle(color: AppColorsDark.mainColor),),
                      style: OutlinedButton.styleFrom(
                        side:BorderSide(color: AppColorsDark.bgCardColor, width: 2), // سمك وحدود الزر
                        foregroundColor: AppColorsDark.mainColor, // لون النص والأيقونات
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(color: Colors.white70),
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
                          date: _selectedDate.subtract(const Duration(days: 1))),
                      child: const Text('اليوم السابق'),
                    ),
                    OutlinedButton(
                      onPressed: () => _loadShifts(
                          date: _selectedDate.add(const Duration(days: 1))),
                      child: const Text('اليوم التالي'),
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
    final int perRow = constraints.maxWidth < 900
        ? 1
        : (constraints.maxWidth < 1200 ? 2 : 3);

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
        // لا تمرر locale: Locale('ar') إن لم تضبط localizationsDelegates (لقد وضّحت أعلاه)
      );
    } catch (e, st) {
      debugPrint('showDatePicker error: $e\n$st');
      // كحل مؤقت افتح date picker بدون locale أو استخدم حوار بديل
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ في اختيار التاريخ — حاول مجدداً',
          textAlign: TextAlign.right,

        )));
      }
      return;
    }
    if (picked != null) {
      await _loadShifts(date: picked);
    }
  }




  Widget _desktopLayout(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.clamp(800.0, 1400.0);

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
                  margin: const EdgeInsets.only(right: 12.0, top: 8.0, bottom: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(child: Text('تعيين المبلغ المبدئي في الدرج', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                      const SizedBox(height: 20),
                      CustomFormField(
                        controller: _startingController,
                        hint: 'تعيين المبلغ المبدئي في الدرج',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 20),
                      CustomButton(text: 'حفظ القيمه للدرج', onPressed: _saveStartingAmount_replace, infinity: true, color: AppColorsDark.mainColor.withOpacity(0.9)),
                      const SizedBox(height: 20),
                      Center(child: Text('وضع الحد الاقصي لبدايه الدرج بعد تقفيل الشيفت', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white), textAlign: TextAlign.center)),
                      const SizedBox(height: 20),
                      CustomFormField(
                        controller: _maxLimitController,
                        hint: 'وضع الحد الاقصي لبدايه الدرج بعد تقفيل الشيفت',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 20),
                      CustomButton(text: 'حفظ الحد الأقصى', onPressed: _saveMaxLimit, infinity: true, color: AppColorsDark.mainColor.withOpacity(0.7)),
                      const SizedBox(height: 20),
                      Divider(height: 30, color: AppColorsDark.mainColor),
                      Center(child: Text('تعيين/تعديل رصيد المحفظة الإلكترونية', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                      const SizedBox(height: 12),
                      CustomFormField(controller: _walletController, hint: 'EGP رصيد المحفظة', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                      const SizedBox(height: 20),
                      CustomButton(text: 'حفظ القيمه للمحفظة', onPressed: _addToWallet, infinity: true, color: AppColorsDark.mainColor.withOpacity(0.5)),
                      const SizedBox(height: 20),
                      Divider(height: 30, color: AppColorsDark.mainColor),
                      Center(child: Text('ملخص سريع', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                      const SizedBox(height: 10),
                      _buildSummaryRow('المبلغ في الدرج الآن', _totalInDrawer),
                      const SizedBox(height: 10),
                      _buildSummaryRow('صافي مبيعات نقدي', _salesNet),
                      const SizedBox(height: 10),
                      _buildSummaryRow('صافي مبيعات المحفظة الإلكترونية', _cashInWallet),
                      const SizedBox(height: 10),
                      _buildSummaryRow('مدفوعات مشتريات (نقدي)', _purchasePaidCash),
                      const SizedBox(height: 8),
                      _buildSummaryRow("المدفوع (مشتريات آجلة)",   _purchasePaidOnCredit),
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
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.bgCardColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Center(child: Text('المبلغ البدايه للدرج', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                                    const SizedBox(height: 12),
                                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                                      Text("جنيه", style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(width: 10),
                                      // نعرض القيمة المقروءة من السيرفر هنا — غير قابلة للتحرير من الواجهة
                                      Text(_formatWithSign(_startingAmount), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ])),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 200,
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.bgCardColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Center(child: Text('الحد الادني لبدايه كل شيفت', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                                    const SizedBox(height: 12),
                                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                                      Text("جنيه", style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(width: 10),
                                      // نعرض القيمة المقروءة من السيرفر هنا — غير قابلة للتحرير من الواجهة
                                      Text(_formatWithSign(_maxLimit), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ])),
                                  ]),
                                ),
                              ),
                            ),
                          ),                        ]),
                      ),
                      SizedBox(height: 15,),
                     Directionality(
                        textDirection: TextDirection.rtl,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('تقفيلات الشيفت الخاصة بكل كاشير', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white)),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: _pickDateAndReload,
                                    icon: const Icon(Icons.calendar_today, color: Colors.white),
                                    label: Text(_dateFormat.format(_selectedDate), style: const TextStyle(color: Colors.white)),
                                    style: TextButton.styleFrom(backgroundColor: Colors.transparent),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _loadShifts(date: _selectedDate),
                                    icon: const Icon(Icons.refresh, color: Colors.white),
                                  )
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // المحتوى: شبكة/قائمة البطاقات
                          _buildShiftsGrid(constraints),
                          const SizedBox(height: 12),
                        ]),
                  ),
                      /////////////////////

                     SizedBox(height: 20,),

                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                        child: Row(children: [
                          Expanded(
                            child: SizedBox(
                              height: 200,
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.bgCardColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Center(child: Text('الاجمالي في الدرج لكل الشيفتات', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white,height: 1.5),textAlign: TextAlign.center,)),
                                    const SizedBox(height: 12),
                                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                                      Text("جنيه", style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(width: 10),
                                      // نعرض القيمة المقروءة من السيرفر هنا — غير قابلة للتحرير من الواجهة
                                      Text(_formatWithSign(_totalInDrawer), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ])),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 200,
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.bgCardColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                    Center(child: Text('الاجمالي في المحفظه لكل الشيفتات', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white,height: 1.5),textAlign: TextAlign.center,)),
                                    const SizedBox(height: 12),
                                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Text("جنيه", style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                        const SizedBox(width: 10),
                                        Text(_formatMoney(_cashInWallet), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                      ]),
                                    ])),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 200,
                              child: Card(
                                elevation: 3,
                                color: AppColorsDark.mainColor.withOpacity(0.08),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Center(child: Text('الفواتير الاجله التي لم يتم دفعها', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Colors.white))),
                                    const SizedBox(height: 12),
                                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Text("جنيه", style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(width: 10),
                                      Text(_formatMoney(_creditOutstanding), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ])),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),


                    ]),
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
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text('الدرج والتقارير', style: TextStyle(fontSize: 27, color: Colors.white)),
        actions: [IconButton(onPressed: () {
          _loadData();
          _loadShifts(date: _selectedDate);
        }, icon: const Icon(Icons.refresh))],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : LayoutBuilder(builder: (context, constraints) {
        return _desktopLayout(constraints);
      }),
    );
  }
}

// ---------- نموذج بيانات لتقفيلة الشيفت ----------
class CloseShift {
  final String cashierName;
  final double totalInDrawer;
  final double totalInWallet;
  final Map<String, dynamic>? raw;

  CloseShift({
    required this.cashierName,
    required this.totalInDrawer,
    required this.totalInWallet,
    this.raw,
  });
}
