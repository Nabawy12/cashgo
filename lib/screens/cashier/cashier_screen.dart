// lib/screens/cashier/cashier_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:cashgo/models/login.dart';
import 'package:cashgo/services/cashier/close_shieft.dart';
import 'package:cashgo/services/cashier/profit_api.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection ;
import 'package:shimmer/shimmer.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/cart.dart';
import '../../models/cashier/profit.dart';
import '../../models/product.dart';
import '../../services/Api/Admin/Products.dart';
import '../../services/Api/Admin/financle.dart';
import '../../services/cashier/deposit.dart';
import '../../services/cashier/print.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/cartlist.dart';
import '../../widgets/Cashier/close_shieft.dart';
import '../../widgets/Cashier/payment_controller.dart';
import '../../widgets/Cashier/receipt_widget.dart';
import '../../widgets/Loading/cashier/cart.dart';
import '../shared/login_screen.dart';
import 'ReceiveFromSupplier.dart';
import 'histroy.dart';

// ضع هذه التعاريف أعلى الملف (قبل CashierScreen)
class ArrowDownIntent extends Intent { const ArrowDownIntent(); }
class ArrowUpIntent extends Intent { const ArrowUpIntent(); }
class EnterIntent extends Intent { const EnterIntent(); }
class EscapeIntent extends Intent { const EscapeIntent(); }


class CashierScreen extends StatefulWidget {
  static const routName = "/Cashier";
  final String cashierUsername;
  const CashierScreen({super.key, this.cashierUsername = 'cashier'});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  final TextEditingController _paidController = TextEditingController();
  final Map<int, CartItem> _cart = {};
  bool _saving = false;

  final GlobalKey _receiptKey = GlobalKey();

  String? _currentUsername; // اسم الكاشير الحقيقي المأخوذ من DB

  // --- card/wallet totals to show to cashier ---
  double _walletAmount = 0.0;        // latest card_wallet amount
  double _cardReceived = 0.0;       // untransferred card payments from sales
  double _cardTotalAvailable = 0.0; // wallet + untransferred
  double Drawer = 0.0; // wallet + untransferred
  ////////////////////////////
  double _startingAmount = 0.0;
  double _cashInWallet = 0.0;
  double? _totalCash;
  double? _totalWallet;
  double? _cash_with_credit;
  double? _purchases_paid;
  double? _purchases_credit;
  double? _wallet_received;
  double? _cash_received;
  bool _isExchange = false;
  bool _loading = false;
  String? _error;
  ////////////////
  bool _dialogOpening = false;
  final nameFocus = FocusNode();



  // --------- Discount state ----------
  // design: percent-only discount (as requested), from 0% to 50% step 5
  String _discountType = 'percent'; // 'percent' أو 'amount'
  double _discountValue = 0.0; // e.g. 5.0 means 5%
  List<Map<String, dynamic>> _inlineSearchResults = [];
  bool _inlineLoading = false;
  Timer? _inlineDebounce;
  int _inlineSelectedIndex = -1;
  // user-specific starting + net sales (to show in AppBar)
  double _userStarting = 0.0;
  double _userNetSales = 0.0;
  double get _userStartingPlusNet => (_userStarting + _userNetSales);
/////////////////////
  final ScrollController _inlineScrollController = ScrollController();
  final FocusNode _inlineKeyboardNode = FocusNode();




  Future<void> _scrollInlineToIndex(int index) async {
    if (!_inlineScrollController.hasClients) return;
    final itemHeight = 72.0; // تقريب ارتفاع ListTile؛ عدِّل لو كان مختلف
    final offset = (index * itemHeight).clamp(0.0, _inlineScrollController.position.maxScrollExtent);
    await _inlineScrollController.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }



  void _scheduleInlineSearch(String q) {
    _inlineDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _inlineSearchResults = [];
        _inlineLoading = false;
      });
      return;
    }
    _inlineDebounce = Timer(const Duration(milliseconds: 300), () => _runInlineSearch(q));
  }

  Future<void> _runInlineSearch(String q) async {
    setState(() {
      _inlineLoading = true;
    });
    try {
      final rows = await _searchProductsByNameApi(q, limit: 50);
      setState(() {
        _inlineSearchResults = rows;
      });
    } catch (e) {
      debugPrint('inline search (API) error: $e');
      setState(() {
        _inlineSearchResults = [];
      });
    } finally {
      if (mounted) setState(() => _inlineLoading = false);
    }
  }

  StreamSubscription<dynamic>? _connSub; // مرن لقبول أي StreamSubscription

  StreamSubscription? _finBoxSub; // استماع لصندوق financial_accounts
  Box? _financialBox; // cache للصندوق المحلي

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocus);
    });
    _loadCurrentUser();
    WakelockPlus.enable();

    // استمع لـ Hive local financials + حاول جلب من السيرفر
    _initFinancialsListener();
    _loadFinancials(); // محفوظة لديك — ممكن تبقى مُحدّثة لعمل sync عند online

    _loadTotalProfit();
    _loadFinancialsFromLocal().then((_) => _loadFinancials()); // _loadFinancials يحاول السيرفر بعد المحلي
    Session.updateDateTime();

    // موجود بالفعل: _connSub subscription...
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      if (event != ConnectivityResult.none) {
        // الشبكه رجعت — نعمل مزامنة للسجلات المالية من السيرفر لو متوفر
        try {
          await _fetchAndSyncFinancialsFromServer();
        } catch (e, st) {
          debugPrint('[UI] fetchAndSyncFinancialsFromServer failed: $e');
        }
        // بقية الشيفرة الموجودة...
        final metaBox = await Hive.openBox('meta');
        await metaBox.put('lastOfflineSale', 0.0);
        debugPrint('[UI] cleared lastOfflineSale due to connectivity regained');
        final v = await _getLastOfflineSale();
        if (!mounted) return;
        setState(() => _lastOfflineSale = v);
      }
    });
  }

  Future<void> _initFinancialsListener() async {
    try {
      _financialBox = await Hive.openBox('financial_accounts');
      // load once
      await _applyLatestFinancialFromBox();
      // listen for changes
      _finBoxSub?.cancel();
      _finBoxSub = _financialBox!.watch().listen((event) {
        // كل مرة يتغير الصندوق نقرأ اخر سجل
        _applyLatestFinancialFromBox();
      });
    } catch (e, st) {
      debugPrint('[Financials] _initFinancialsListener error: $e\n$st');
    }
  }

  Future<void> _attachFinancialsHiveListener() async {
    try {
      final box = await Hive.openBox('financial_accounts');
      // استماع لتغييرات الصندوق
      box.watch().listen((event) {
        // event.key, event.value
        if (!mounted) return;
        _loadFinancialsFromLocal(); // كل ما اتغير صندوق نعيد تحميل القيم المحلية
      });
    } catch (e) {
      debugPrint('Failed to attach financials listener: $e');
    }
  }

  Future<void> _loadFinancialsFromLocal() async {
    try {
      final box = await Hive.openBox('financial_accounts');
      if (box.isEmpty) {
        setState(() {
          _startingAmount = 0.0;
          _cashInWallet = 0.0;
          _financialsLoaded = true;
        });
        return;
      }
      // خذ آخر سجل (أو اختَر حسب منطقك)
      final lastKey = box.keys.toList().last;
      final raw = Map<String, dynamic>.from(box.get(lastKey) as Map);
      final localStart = double.tryParse((raw['starting_amount'] ?? raw['startingAmount'] ?? '0').toString().replaceAll(',', '')) ?? 0.0;
      final localWallet = double.tryParse((raw['cash_in_wallet'] ?? raw['cashInWallet'] ?? '0').toString().replaceAll(',', '')) ?? 0.0;

      if (!mounted) return;
      setState(() {
        _startingAmount = localStart;
        _cashInWallet = localWallet;
        _financialsLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load local financials: $e');
    }
  }

  bool _financialsLoaded = false;

  Future<void> _applyLatestFinancialFromBox() async {
    try {
      if (!mounted) return;
      if (_financialBox == null || _financialBox!.isEmpty) {
        setState(() {
          _startingAmount = 0.0;
          _cashInWallet = 0.0;
          _totalCash = 0.0;
          _totalWallet = 0.0;
          _financialsLoaded = true; // حتى لو فاضي، نوقف الـ loading
        });
        return;
      }

      final keys = _financialBox!.keys.toList();
      if (keys.isEmpty) {
        setState(() {
          _startingAmount = 0.0;
          _cashInWallet = 0.0;
          _totalCash = 0.0;
          _totalWallet = 0.0;
          _financialsLoaded = true;
        });
        return;
      }

      final lastKey = keys.last;
      final raw = _financialBox!.get(lastKey);
      final Map<String, dynamic> row = _toMapFlexible(raw);

      double pickVal(List<String> candidates) {
        for (final k in candidates) {
          if (row.containsKey(k) && row[k] != null) {
            final v = row[k];
            if (v is num) return v.toDouble();
            if (v is String) {
              final s = v.replaceAll(',', '').trim();
              final d = double.tryParse(s);
              if (d != null) return d;
            }
          }
        }
        return 0.0;
      }

      final localStart = pickVal(['starting_amount', 'startingAmount', 'start', 'start_amount']);
      final localWallet = pickVal(['cash_in_wallet', 'cashInWallet', 'wallet', 'wallet_amount']);

      // لو عندك قيم إجماعية (totalCash/totalWallet) المعرفة في recs سابقًا ضعها هنا
      final localTotalCash = pickVal(['total_in_drawer', 'totalCash', 'total_cash']);
      final localTotalWallet = pickVal(['total_in_wallet', 'totalWallet', 'total_wallet']);

      setState(() {
        _startingAmount = localStart;
        _cashInWallet = localWallet;
        _totalCash = localTotalCash;    // غير null => _moneyOrShimmer يظهر القيمة
        _totalWallet = localTotalWallet; // غير null => يظهر القيمة
        _financialsLoaded = true;
      });
    } catch (e, st) {
      debugPrint('[Financials] _applyLatestFinancialFromBox error: $e\n$st');
      // لو فشل، على الأقل نوقف الـ shimmer و نعرض صفر
      if (mounted) {
        setState(() {
          _startingAmount = 0.0;
          _cashInWallet = 0.0;
          _totalCash = 0.0;
          _totalWallet = 0.0;
          _financialsLoaded = true;
        });
      }
    }
  }

  Widget _moneyOrShimmerWithFlag({double? value, bool withSign = false, bool asInt = true}) {
    if (!_financialsLoaded) {
      // عرض shimmer أثناء انتظار أول قراءة (أونلاين أو أوفلاين)
      return _shimmerMoney(width: 64, height: 16);
    }
    // لو جاهز لكن القيمة لا تزال null (نعتبرها صفر)
    final v = value ?? 0.0;
    final text = withSign ? _formatWithSign(v) : NumberFormat("#,###").format(asInt ? v.toInt() : v);
    return Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14));
  }


  Map<String, dynamic> _toMapFlexible(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {
        final out = <String, dynamic>{};
        raw.forEach((k, v) => out[k.toString()] = v);
        return out;
      }
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  Future<void> _fetchAndSyncFinancialsFromServer() async {
    try {
      // استخدم نفس خدمة InsertFinancialAccountService.getLatest() الموجودة عندك
      final list = await _service.getLatest(limit: 5); // جيب آخر 5 أو 1 حسب رغبتك
      if (list.isEmpty) return;

      // نحول كل FinancialAccount إلى Map ونخزنهم في صندوق financial_accounts
      final box = await Hive.openBox('financial_accounts');
      for (final rec in list) {
        final key = rec.id?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        await box.put(key, rec.toJsonFull());
      }

      // بعد التخزين حدّث الحالة من الصندوق (ستلتقطه الـ listener تلقائيًا لكن نضرب تحميل احتياطي)
      await _applyLatestFinancialFromBox();
      debugPrint('[Financials] synced ${list.length} financial records locally');
    } catch (e, st) {
      debugPrint('[Financials] _fetchAndSyncFinancialsFromServer error: $e\n$st');
    }
  }



  Future<void> _loadCurrentUser() async {
    try {
      final cur = await DBHelper.instance.getCurrentUser();
      if (cur != null) {
        setState(() {
          _currentUsername = (cur['username'] ?? '').toString();
        });
        Session.currentUsername = _currentUsername;
        Session.currentRole = (cur['role'] ?? Session.currentRole) as String?;
        // تحميل بداية الدرج وصافي المبيعات الخاص بالمستخدم الآن بعد معرفة اسمه
      } else {
        // fallback to widget prop if DB has no current user
        setState(() {
          _currentUsername = widget.cashierUsername;
        });
        // and still try to load
      }
    } catch (e) {
      debugPrint('Failed to load current user: $e');
      setState(() {
        _currentUsername = widget.cashierUsername;
      });
    }
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTotalProfit();
    final args = ModalRoute.of(context)?.settings.arguments;

    String usernameFromArgs = '';
    String roleFromArgs = '';

    if (args is Map) {
      usernameFromArgs = (args['username'] ?? '').toString();
      roleFromArgs = (args['role'] ?? '').toString();
    }

    // أفضلية: args > Session > widget prop > ''
    final resolvedUsername = usernameFromArgs.isNotEmpty
        ? usernameFromArgs
        : (Session.currentUsername!.isNotEmpty? Session.currentUsername : (widget.cashierUsername ?? ''));

    final resolvedRole = roleFromArgs.isNotEmpty
        ? roleFromArgs
        : (Session.currentRole!.isNotEmpty ? Session.currentRole : '');

    setState(() {
      _currentUsername = resolvedUsername;
    });

    // ضع Session صراحةً لو احتجت
    Session.currentUsername = resolvedUsername;
    if (resolvedRole!.isNotEmpty) Session.currentRole = resolvedRole;

    // متابعة تحميل البيانات
  }


  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _paidController.dispose();
    _inlineDebounce?.cancel();
    _inlineScrollController.dispose();
    _inlineKeyboardNode.dispose();
    WakelockPlus.disable();

    _service.dispose();

    _finBoxSub?.cancel(); // <-- تأكد إيقاف الاستماع هنا
    super.dispose();
  }

  bool _isLoading = false;


  Future<void> _onBarcodeSubmitted(String code) async {
    final barcode = code.trim();
    if (barcode.isEmpty) return;
    if (_isLoading) return; // منع أي طلب متكرر أثناء التحميل

    setState(() => _isLoading = true);

    try {
      // جلب المنتج من الـ API (يرجع null لو مش موجود)
      final apiProduct = await ProductApi.getProductByBarcode(barcode);

      if (apiProduct == null) {
        // لم يتم العثور على المنتج عبر الـ API
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'المنتج بالباركود $barcode غير موجود',
                textDirection: TextDirection.rtl,
              )
          ),
        );
        return;
      }

      // تحويل إلى نموذج المنتج والتعامل كالسابق
      final product = Product.fromMap(apiProduct);
      final available = product.totalUnits;
      final pid = product.id!;
      final alreadyInCart = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;

      if (available <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
            'الكمية نفدت',
          textDirection: TextDirection.rtl,

        )));
        return;
      }
      if (alreadyInCart + 1 > available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
            'لا يمكن إضافة أكثر من المتاح',
          textDirection: TextDirection.rtl,

        )));
        return;
      }

      // تحديث الكارت
      setState(() {
        if (_cart.containsKey(pid)) {
          _cart[pid]!.quantity += 1;
        } else {
          _cart[pid] = CartItem(product: product, quantity: 1);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'حدث خطأ أثناء التحميل',
        textDirection: TextDirection.rtl,

      )));
    } finally {
      // مهم: تأكد أن الـ widget ما اتلف قبل التحديث
      if (!mounted) return;
      setState(() => _isLoading = false);

      // تنظيف الحقل وإعادة الفوكس
      _barcodeController.clear();
      FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }

  /// Dialog يعرِض أسماء المنتجات فقط، ويُرجع خريطة المنتج المختار أو null عند الإلغاء.
  Future<Map<String, dynamic>?> showProductChoiceDialog(
      BuildContext context,
      List<Map<String, dynamic>> products,
      ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppColorsDark.bgColor,
            title: Center(child: const Text('اختر المنتج', style: TextStyle(color: Colors.white))),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 0.5),
                itemBuilder: (context, i) {
                  final name = (products[i]['name'] ?? '').toString();
                  return ListTile(
                    title: Text(name, style: TextStyle(color: Colors.white, fontSize: 20)),
                    onTap: () {
                      Navigator.of(context).pop(products[i]);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor,
                ),
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  double get _total => computeTotal(_cart);
  double get _paid => double.tryParse(_paidController.text.replaceAll(',', '')) ?? 0.0;

  // effective total after applying invoice-level discount
  double get _effectiveTotal {
    final subtotal = _total;

    if (_discountType == 'percent' && _discountValue > 0) {
      final disc = subtotal * (_discountValue / 100.0);
      return (subtotal - disc).clamp(0.0, double.infinity);
    } else if (_discountType == 'amount' && _discountValue > 0) {
      return (subtotal - _discountValue).clamp(0.0, double.infinity);
    }

    return subtotal;
  }


  void _addQuickPaid(double amount) {
    final current = _paid;
    final newPaid = current + amount;
    _paidController.text = newPaid.toStringAsFixed(2);
    setState(() {});
  }

  void _setQuickPaid(double amount) {
    _paidController.text = amount.toStringAsFixed(2);
    setState(() {});
  }

  /// ===== API-based product helpers =====

  /// جلب كل المنتجات من الـ API ثم فلترة حسب الباركود (لأن قد يكون عندك أكثر من منتج بنفس الباركود)
  Future<List<Map<String, dynamic>>> _getProductsByBarcodeListFromApi(String barcode) async {
    try {
      final all = await ProductApi.getAllProducts();
      final code = barcode.trim();
      if (code.isEmpty) return [];
      final matches = all.where((p) => (p['barcode']?.toString() ?? '').trim() == code).toList();
      return matches;
    } catch (e) {
      debugPrint('API barcode list error: $e');
      return [];
    }
  }

  /// جلب منتج واحد من الـ API بالباركود (ترجع null لو مفيش)
  Future<Map<String, dynamic>?> _getProductByBarcodeFromApi(String barcode) async {
    try {
      return await ProductApi.getProductByBarcode(barcode.trim());
    } catch (e) {
      debugPrint('API get product by barcode error: $e');
      return null;
    }
  }

  /// بحث بالاسم عبر الـ API:
  /// ملاحظة: لو الـ API يدعم بحث سيرفر-side من الأفضل استدعاؤه مباشرة — هنا نعمل جلب لكل المنتجات ثم نفلتر محلياً.
  Future<List<Map<String, dynamic>>> _searchProductsByNameApi(String q, {int limit = 50}) async {
    try {
      final all = await ProductApi.getAllProducts();
      final needle = q.trim().toLowerCase();
      if (needle.isEmpty) return [];
      final results = all.where((p) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        return name.contains(needle);
      }).take(limit).toList();
      return results;
    } catch (e) {
      debugPrint('API search by name error: $e');
      return [];
    }
  }


  void _changeQuantity(int productId, int newQty) async {
    if (!_cart.containsKey(productId)) return;
    final productMap = await ProductApi.getProductByBarcode((_cart[productId]!.product.barcode));
    if (productMap == null) return;
    final product = Product.fromMap(productMap);
    final available = product.totalUnits;
    if (newQty <= 0) {
      setState(() => _cart.remove(productId));
    } else if (newQty > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'لا توجد كمية كافية',
        textDirection: TextDirection.rtl,

      )));
    } else {
      setState(() => _cart[productId]!.quantity = newQty);
    }
  }

  Future<void> _editQuantityDialog(int productId) async {
    if (!_cart.containsKey(productId)) return;
    final current = _cart[productId]!.quantity;
    final controller = TextEditingController(text: current.toString());
    final res = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الكمية'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'ادخل الكمية (قطع)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () { final v = int.tryParse(controller.text) ?? current; Navigator.of(ctx).pop(v); }, child: const Text('موافق')),
        ],
      ),
    );
    if (res != null) _changeQuantity(productId, res);
  }

  // دالة جديدة تطلب اسم العميل عند حفظ فاتورة آجل
  Future<String?> _askForCustomerName() async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SizedBox(
        width: 250,
        height: 50,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: Center(child: const Text('اسم العميل للفاتورة الآجلة', style: TextStyle(color: Colors.white))),
          content: CustomFormField(
            controller: controller,
            hint: 'اكتب اسم العميل أو الجهة',
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
            ),
            CustomButton(
              infinity: false,
              text: 'حفظ',
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    return res;
  }

  // ===================================================================
  // === Functions to show and maintain combined card/wallet totals ====
  // ===================================================================

  /// Safely compute the true untransferred card amount.
  /// Works across DB versions (supports card_transferred_amount or card_transferred flag if present).
  final NumberFormat _moneyFmt = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  final NumberFormat _moneyFmtNoDecimal = NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 0);
  String _formatMoney(double value) {
    const eps = 0.000001;
    final isWhole = (value - value.truncate()).abs() < eps;
    // Fixed: avoid recursive call. Use decimal format when needed.
    return isWhole ? _moneyFmtNoDecimal.format(value) : _moneyFmt.format(value);
  }
  String _formatWithSign(double value) {
    if (value < 0) {
      return '-${_formatMoney(value.abs())}';
    }
    return _formatMoney(value);
  }


  Future<void> _openCardWalletDialog() async {
    final username = _currentUsername ?? widget.cashierUsername;
    bool isDeposit = true;
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isProcessing = false;
        String? errorMessage; // 🔴 هنا الرسالة

        return StatefulBuilder(builder: (ctx2, setState2) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: const Center(
                child: Text('المحفظة الالكترونيه', style: TextStyle(color: Colors.white)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isDeposit
                        ? 'الرصيد الحالي للمحفظة: ${((_totalWallet ?? 0) + (_cashInWallet ?? 0)).toStringAsFixed(0)}'
                        : 'الرصيد الحالي للدرج: ${((_totalCash ?? 0) + (_startingAmount ?? 0)).toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isDeposit ? Colors.green : AppColorsDark.bgColor),
                          onPressed: isProcessing ? null : () => setState2(() {
                            isDeposit = true;
                            errorMessage = null;
                          }),
                          child: const Text('إيداع', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: !isDeposit ? Colors.red : AppColorsDark.bgColor),
                          onPressed: isProcessing ? null : () => setState2(() {
                            isDeposit = false;
                            errorMessage = null;
                          }),
                          child: const Text('سحب', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CustomFormField(
                    controller: controller,
                    hint: 'ادخل المبلغ',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 17),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                CustomButton(
                  infinity: false,
                  text: 'تنفيذ',
                  onPressed: isProcessing
                      ? null
                      : () async {
                    final raw = controller.text.trim();
                    final value = double.tryParse(raw.replaceAll(',', '')) ?? 0.0;

                    if (value <= 0) {
                      setState2(() => errorMessage = 'أدخل مبلغًا صحيحًا');
                      return;
                    }

                    // ✅ التحقق من الرصيد
                    final availableWallet = (_totalWallet ?? 0) + (_cashInWallet ?? 0);
                    final availableCash = (_totalCash ?? 0) + (_startingAmount ?? 0);

                    if (isDeposit && value > availableWallet) {
                      setState2(() => errorMessage = 'المبلغ أكبر من الرصيد الحالي بالمحفظة');
                      return;
                    }
                    if (!isDeposit && value > availableCash) {
                      setState2(() => errorMessage = 'المبلغ أكبر من الرصيد الحالي بالدرج');
                      return;
                    }

                    // مفيش خطأ = نكمل العملية
                    setState2(() {
                      isProcessing = true;
                      errorMessage = null;
                    });

                    try {
                      final api = ProfitApi();
                      final resp = await api.send(
                        cashierName: username,
                        depositFromCashToWallet: isDeposit ? 0.0 : value,
                        depositFromWalletToCash: isDeposit ? value : 0.0,
                      );

                      Navigator.of(ctx).pop();
                      // تقدر تعرض SnackBar هنا لو عايز نجاح العملية
                    } catch (e) {
                      setState2(() => errorMessage = 'فشل تنفيذ العملية');
                    } finally {
                      setState2(() => isProcessing = false);
                    }
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }


  // ------------- Discount dialog -------------


  Future<void> _openNameSearchDialog({String initialQuery = ''}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            List<Map<String, dynamic>> results = [];
            bool loading = false;
            Timer? debounce;
            final controller = TextEditingController(text: initialQuery);
            final FocusNode textFocus = FocusNode();
            final FocusNode keyFocus = FocusNode();
            final ScrollController scrollController = ScrollController();
            int selectedIndex = -1;

            Future<void> runSearch(String q) async {
              setState2(() => loading = true);
              try {
                final rows = await DBHelper.instance.searchProductsByName(q, limit: 50);
                setState2(() {
                  results = rows;
                  selectedIndex = results.isNotEmpty ? 0 : -1;
                });
              } catch (e) {
                debugPrint('searchProductsByName error: $e');
                setState2(() { results = []; selectedIndex = -1; });
              } finally {
                setState2(() => loading = false);
              }
            }

            void scheduleSearch(String q) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () {
                if (q.trim().isNotEmpty) runSearch(q);
                else setState2(() { results = []; selectedIndex = -1; });
              });
            }

            void ensureSelectedVisible() {
              if (!scrollController.hasClients || selectedIndex < 0) return;
              const itemHeight = 72.0;
              final offset = (selectedIndex * itemHeight).clamp(0.0, scrollController.position.maxScrollExtent);
              scrollController.animateTo(offset, duration: const Duration(milliseconds: 150), curve: Curves.easeInOut);
            }

            void _ensureKeyFocusAndUnfocusTextIfNeeded() {
              if (textFocus.hasFocus) {
                try { textFocus.unfocus(); } catch (_) {}
              }
              if (!keyFocus.hasFocus) {
                FocusScope.of(ctx2).requestFocus(keyFocus);
              }
            }

            if (initialQuery.trim().isNotEmpty && results.isEmpty && !loading) {
              Future.microtask(() => runSearch(initialQuery));
            }
            String customInputText = controller.text;

            Widget buildCustomInput() {
              return GestureDetector(
                onTap: () {
                  // اطلب الفوكس لكي نلتقط مفاتيح الكيبورد عبر RawKeyboardListener
                  if (!textFocus.hasFocus) FocusScope.of(ctx2).requestFocus(textFocus);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColorsDark.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          customInputText.isEmpty ? 'اكتب اسم المنتج...' : customInputText,
                          style: TextStyle(
                            color: customInputText.isEmpty ? Colors.white38 : Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (loading)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator())
                      else if (customInputText.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () {
                            setState2(() {
                              customInputText = '';
                              controller.text = '';
                              results = [];
                              selectedIndex = -1;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              );
            }

            return Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.arrowDown): const ArrowDownIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowUp): const ArrowUpIntent(),
                LogicalKeySet(LogicalKeyboardKey.enter): const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.numpadEnter): const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ArrowDownIntent: CallbackAction<ArrowDownIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex = (selectedIndex + 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  ArrowUpIntent: CallbackAction<ArrowUpIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex = (selectedIndex - 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  EnterIntent: CallbackAction<EnterIntent>(onInvoke: (intent) {
                    if (selectedIndex >= 0 && selectedIndex < results.length) {
                      final item = results[selectedIndex];
                      if (_dialogOpening) return null;
                      _dialogOpening = true;
                      Future.microtask(() async {
                        try {
                          await _showProductDetailDialog(item);
                        } finally {
                          if (!mounted) return;
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                            _dialogOpening = false;
                          });
                        }
                      });
                    } else {
                      if (controller.text.trim().isNotEmpty) runSearch(controller.text.trim());
                    }
                    return null;
                  }),
                  EscapeIntent: CallbackAction<EscapeIntent>(onInvoke: (intent) {
                    Navigator.of(ctx2).pop();
                    return null;
                  }),
                },

                child: RawKeyboardListener(
                  focusNode: textFocus,
                  onKey: (RawKeyEvent event) {
                    if (event is RawKeyDownEvent) {
                      final key = event.logicalKey;

                      // handle printable characters (event.character may be null on some platforms, but often works on macOS)
                      final char = (event.character ?? '');
                      if (char.isNotEmpty && char.codeUnitAt(0) != 10 && !event.isControlPressed && !event.isMetaPressed) {
                        // append printable character
                        setState2(() {
                          customInputText += char;
                          controller.text = customInputText;
                        });
                        scheduleSearch(customInputText);
                        return;
                      }

                      if (key == LogicalKeyboardKey.backspace) {
                        setState2(() {
                          if (customInputText.isNotEmpty) {
                            customInputText = customInputText.substring(0, customInputText.length - 1);
                            controller.text = customInputText;
                            if (customInputText.trim().isEmpty) {
                              results = [];
                              selectedIndex = -1;
                            } else {
                              scheduleSearch(customInputText);
                            }
                          }
                        });
                        return;
                      }

                      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
                        // نفّذ بحث نهائي أو افتح العنصر المختار
                        if (customInputText.trim().isNotEmpty && results.isEmpty) {
                          runSearch(customInputText.trim());
                        } else if (selectedIndex >= 0 && selectedIndex < results.length) {
                          final item = results[selectedIndex];
                          if (_dialogOpening) return;
                          _dialogOpening = true;
                          Future.microtask(() async {
                            try {
                              await _showProductDetailDialog(item);
                            } finally {
                              if (!mounted) return;
                              setState(() {
                                _inlineSearchResults = [];
                                _inlineLoading = false;
                                _inlineSelectedIndex = -1;
                                _dialogOpening = false;
                              });
                            }
                          });
                        }
                        return;
                      }

                      if (key == LogicalKeyboardKey.escape) {
                        Navigator.of(ctx2).pop();
                        return;
                      }

                      // arrows: نحول الفوكس إلى keyFocus لأننا نريد أنها تستخدم لتنقّل النتائج
                      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
                        // ننقل الفوكس لالتقاط الأسهم في المكان اللي يتعامل مع التنقّل (keyFocus موجود في الـ dialog)
                        if (!keyFocus.hasFocus) FocusScope.of(ctx2).requestFocus(keyFocus);

                        // وإذا أردتي يمكن هنا أيضًا التحكم المباشر بتغيير selectedIndex
                        if (results.isNotEmpty) {
                          setState2(() {
                            if (key == LogicalKeyboardKey.arrowDown) {
                              selectedIndex = (selectedIndex + 1).clamp(0, results.length - 1);
                            } else {
                              selectedIndex = (selectedIndex - 1).clamp(0, results.length - 1);
                            }
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            // scroll to selected
                            const itemHeight = 72.0;
                            if (scrollController.hasClients && selectedIndex >= 0) {
                              final offset = (selectedIndex * itemHeight).clamp(0.0, scrollController.position.maxScrollExtent);
                              scrollController.animateTo(offset, duration: const Duration(milliseconds: 150), curve: Curves.easeInOut);
                            }
                          });
                        }
                        return;
                      }
                    }
                  },
                  child: buildCustomInput(),
                ),
              ),
            );
          }),
        );
      },
    );
  }
  Future<void> _showProductDetailDialog(Map<String, dynamic> product) async {
    if (!product.containsKey('total_units')) {
      final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
      final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
    }

    // NOTE: we intentionally do NOT dispose this controller here to avoid a race where
    // framework tries to re-add listeners while the controller was disposed (hot reload / pop races).
    final qtyController = TextEditingController(text: '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        int qty = 1;
        final available = (product['total_units'] as num?)?.toInt() ?? 0;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            final name = (product['name'] ?? '').toString();
            final price = (product['selling_price'] ?? product['sellingPrice'] ?? 0.0);
            final desc = (product['description'] ?? '').toString();

            // extracted add-to-cart logic so we can call it from button and onSubmitted
            Future<void> addRequested() async {
              final pid = (product['id'] as num?)?.toInt();
              if (pid == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
                    'المنتج غير صالح',
                  textDirection: TextDirection.rtl,

                )));
                return;
              }
              final already = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;
              final requested = qty <= 0 ? 1 : qty; // default 1 if empty or zero
              if (already + requested > available) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
                    'لا توجد كمية كافية',
                  textDirection: TextDirection.rtl,

                )));
                return;
              }

              // Update outer state (the cart)
              if (mounted) {
                setState(() {
                  if (_cart.containsKey(pid)) {
                    _cart[pid]!.quantity += requested;
                  } else {
                    final prodModel = Product.fromMap(product);
                    _cart[pid] = CartItem(product: prodModel, quantity: requested);
                  }
                });
              }

              // close dialog and give feedback
              Navigator.of(ctx2).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                    'تمت إضافة $requested قطعة من ${product['name']}',
                  textDirection: TextDirection.rtl,

                )));
                _barcodeController.clear();
                FocusScope.of(context).requestFocus(_barcodeFocus);
              }
            }

            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Text(name, style: const TextStyle(color: Colors.white)),
              content: SingleChildScrollView( // prevents overflow when keyboard opens
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (desc.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(desc, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.right),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('السعر: ${price.toString()}', style: const TextStyle(color: Colors.white70)),
                          Text('متاح: $available', style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: qty > 1
                                ? () {
                              setState2(() {
                                qty = (qty - 1).clamp(0, available);
                                qtyController.value = TextEditingValue(
                                  text: qty.toString(),
                                  selection: TextSelection.collapsed(offset: qty.toString().length),
                                );
                              });
                            }
                                : null,
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColorsDark.bgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: TextField(
                              controller: qtyController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                              onChanged: (v) {
                                setState2(() {
                                  final trimmed = v.trim();
                                  if (trimmed.isEmpty) {
                                    qty = 0;
                                  } else {
                                    final parsed = int.tryParse(trimmed) ?? 0;
                                    qty = parsed;
                                    if (qty > available) {
                                      qty = available;
                                      qtyController.value = TextEditingValue(
                                        text: qty.toString(),
                                        selection: TextSelection.collapsed(offset: qty.toString().length),
                                      );
                                    }
                                  }
                                });
                              },
                              // handle Enter key as "Add"
                              onSubmitted: (v) async {
                                final trimmed = v.trim();
                                if (trimmed.isEmpty) {
                                  qty = 1;
                                } else {
                                  qty = int.tryParse(trimmed) ?? 1;
                                }
                                if (qty > available) qty = available;
                                await addRequested();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: qty < available
                                ? () {
                              setState2(() {
                                qty = (qty + 1).clamp(0, available);
                                qtyController.value = TextEditingValue(
                                  text: qty.toString(),
                                  selection: TextSelection.collapsed(offset: qty.toString().length),
                                );
                              });
                            }
                                : null,
                            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () {
                    Navigator.of(ctx2).pop();
                    Future.microtask(() {
                      _barcodeController.clear();
                      FocusScope.of(context).requestFocus(_barcodeFocus);
                    });
                  },
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final trimmed = qtyController.text.trim();
                    if (trimmed.isEmpty) {
                      qty = 1;
                    } else {
                      qty = int.tryParse(trimmed) ?? 1;
                    }
                    if (qty > available) qty = available;
                    await addRequested();
                  },
                  child: const Text('أضف إلى السلة'),
                ),
              ],
            );
          }),
        );
      },
    );

    // note: intentionally not disposing qtyController here to avoid a race that causes
    // "used after being disposed" in some hot-reload / pop timing scenarios.
    // If you prefer, you can schedule a dispose later:
    // Future.delayed(Duration(seconds: 5), () { qtyController.dispose(); });
  }
///////////////////////////////////////////////////////////////////////////////
  final InsertFinancialAccountService _service = InsertFinancialAccountService();


// UUID للـ sales ops
  final _uuidForSale = Uuid();

  double _lastOfflineSale = 0.0;   // <-- ضيف هذا السطر هنا جنب _totalCash


  Future<double> _getLastOfflineSale() async {
    final box = await Hive.openBox('meta');
    final v = box.get('lastOfflineSale');
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _setLastOfflineSale(double val) async {
    final box = await Hive.openBox('meta');
    final safeVal = (val.isFinite && val >= 0.0) ? val : 0.0;
    await box.put('lastOfflineSale', safeVal);
  }

  Future<void> _clearLastOfflineSale() async {
    final box = await Hive.openBox('meta');
    await box.put('lastOfflineSale', 0.0);
  }



  Future<void> _saveSale({required bool requireFullPayment, String paymentMethod = 'cash'}) async {
    if (_cart.isEmpty) return;

    // إجمالي قبل الخصم
    final subtotal = _total;

    // طَبّع نوع الخصم ليطابق ReceiptWidget ('percent' أو 'fixed')
    final normalizedDiscountType = (_discountType == 'amount') ? 'fixed' : _discountType;

    // حساب قيمة الخصم والتسمية
    double discountAmount = 0.0;
    String discountLabel = '';
    if (normalizedDiscountType == 'percent' && _discountValue > 0) {
      final pct = _discountValue.clamp(0.0, 100.0);
      discountAmount = subtotal * (pct / 100.0);
      discountLabel = '${pct.toStringAsFixed(0)}%';
    } else if (normalizedDiscountType == 'fixed' && _discountValue > 0) {
      discountAmount = _discountValue > subtotal ? subtotal : _discountValue;
      discountLabel = discountAmount.toStringAsFixed(2);
    }

    // الإجمالي بعد الخصم
    final total = (subtotal - discountAmount).clamp(0.0, double.infinity);

    String? customerName;
    if (paymentMethod == 'credit') {
      customerName = await _askForCustomerName();
      if (customerName == null || customerName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'تم إلغاء حفظ الفاتورة: يجب إدخال اسم العميل للفواتير الآجلة',
            textDirection: TextDirection.rtl,
          )),
        );
        return;
      }
    }

    final paid = (paymentMethod == 'card' || paymentMethod == 'wallet') ? total : _paid;

    if (requireFullPayment && paid < total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'العميل لم يدفع كامل المبلغ',
          textDirection: TextDirection.rtl,
        )),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final cashierNameToUse = Session.currentUsername ?? widget.cashierUsername;
      final changeAmount = (paid >= total) ? (paid - total) : 0.0;

      final List<Map<String, dynamic>> cartPayload = [];
      _cart.forEach((productId, cartItem) {
        cartPayload.add({
          'product_id': productId,
          'barcode': cartItem.product.barcode ?? '',
          'name': cartItem.product.name ?? '',
          'price': cartItem.product.sellingPrice,
          'qty': cartItem.quantity,
        });
      });

      final apiUrl = Uri.parse('https://nabawisolution.com/invoice_reciept.php');

      final payload = {
        'cart': cartPayload,
        'subtotal': subtotal,
        'total': total,
        'paid': paid,
        'requireFullPayment': requireFullPayment,
        'paymentMethod': paymentMethod,
        'cashierUsername': cashierNameToUse,
        'discountType': normalizedDiscountType,
        'discountValue': _discountValue,
        'subtotal_before_discount': subtotal,
        'discount_amount': discountAmount,
        'discount_label': discountLabel,
        'total_after_discount': total,
        'customerName': customerName,
      };

      // حاول ترسل للسيرفر أولًا
      bool serverSaved = false;
      Map<String, dynamic>? serverResponseBody;
      try {
        final resp = await http.post(
          apiUrl,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 12));

        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            serverSaved = true;
            serverResponseBody = Map<String, dynamic>.from(body);
          } else {
            final serverMsg = (body != null && body['error'] != null) ? body['error'] : 'Server returned failure';
            throw Exception(serverMsg);
          }
        } else {
          throw Exception('HTTP ${resp.statusCode}');
        }
      } catch (e) {
        serverSaved = false;
        debugPrint('[saveSale] server save failed: $e');
      }

      // لو السيرفر حفظ: نفس السلوك القديم (تنبيه، طباعة، تنظيف)
      if (serverSaved) {
        final serverMessage = (serverResponseBody?['message'] ?? 'تم الحفظ بنجاح').toString();

        if (paymentMethod == 'credit') {
          final remaining = total - paid;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              'تم حفظ الفاتورة كآجل باسم $customerName — المتبقي: ${remaining.toStringAsFixed(2)}',
              textDirection: TextDirection.rtl,
            )),
          );
        } else if (paymentMethod == 'card') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'تم الحفظ — تم الدفع بالكارت بالكامل',
              textDirection: TextDirection.rtl,
            )),
          );
        } else if (paymentMethod == 'wallet') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              serverMessage,
              textDirection: TextDirection.rtl,
            )),
          );
        } else {
          final beforeStr = subtotal.toStringAsFixed(2);
          final afterStr = total.toStringAsFixed(2);
          final change = (paid - total).toStringAsFixed(2);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              'تم الحفظ — الإجمالي قبل الخصم: $beforeStr  — بعد الخصم: $afterStr  — الباقي: $change',
              textDirection: TextDirection.rtl,
            )),
          );
        }

        // طباعة الإيصال كما كان
        bool printSuccess = false;
        try {
          await Future.delayed(const Duration(milliseconds: 250));
          final printedCart = Map<int, CartItem>.from(_cart);

          final receiptWidget = ReceiptWidget(
            cart: printedCart,
            paid: paid,
            cashierUsername: cashierNameToUse,
            width: 220,
            useCairo: true,
            discountType: normalizedDiscountType,
            discountValue: _discountValue,
          );

          await PrintService.printWidgetUsingOverlay(context, receiptWidget, width: 220, pixelRatio: 2.0);
          printSuccess = true;
          debugPrint('Print succeeded (overlay method).');
        } catch (e, st) {
          debugPrint('Print failed (overlay method): $e\n$st');
        }

        if (!printSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'فشل الطباعة. يمكنك المحاولة لاحقًا من صفحة الطباعة.',
              textDirection: TextDirection.rtl,
            )),
          );
        }

        setState(() {
          _cart.clear();
          _paidController.clear();
          _discountValue = 0.0;
          _discountType = 'percent';
          debugPrint("Cart cleared, items = ${_cart.length}");
        });

        await _loadTotalProfit();
      } else {
        // OFFLINE: خزّن الفاتورة محليًا في sales + ops (كما كنا) + خزن قيمة آخر عملية اوفلاين
        try {
          final opsBox = await Hive.openBox('ops');
          final salesBox = await Hive.openBox('sales');
          final localSaleId = -DateTime.now().millisecondsSinceEpoch;

          final saleRecord = <String, dynamic>{
            'local_id': localSaleId,
            'cart': cartPayload,
            'subtotal': subtotal,
            'total': total,
            'paid': paid,
            'requireFullPayment': requireFullPayment,
            'paymentMethod': paymentMethod,
            'cashierUsername': cashierNameToUse,
            'discountType': normalizedDiscountType,
            'discountValue': _discountValue,
            'discount_amount': discountAmount,
            'discount_label': discountLabel,
            'total_after_discount': total,
            'customerName': customerName,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'sync_state': 'pending',
            'counted_locally': true, // ضع هاش علشان SyncManager يعرف يعالجه لاحقًا
          };

          await salesBox.put(localSaleId.toString(), saleRecord);

          final op = {
            'opId': _uuidForSale.v4(),
            'entity': 'sale',
            'entityId': localSaleId,
            'type': 'create',
            'payload': saleRecord,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'state': 'pending',
            'retries': 0,
          };
          await opsBox.put(op['opId'] as String, op);

          // ---- خزن قيمة آخر عملية اوفلاين هنا ----
          await _setLastOfflineSale(total);
          setState(() => _lastOfflineSale = total);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'لا يوجد اتصال — تم حفظ الفاتورة محليًا وسيتم رفعها عند استعادة الاتصال.',
              textDirection: TextDirection.rtl,
            )),
          );

          // محاولة الطباعة كما سابقًا
          bool printSuccess = false;
          try {
            await Future.delayed(const Duration(milliseconds: 250));
            final printedCart = Map<int, CartItem>.from(_cart);

            final receiptWidget = ReceiptWidget(
              cart: printedCart,
              paid: paid,
              cashierUsername: cashierNameToUse,
              width: 220,
              useCairo: true,
              discountType: normalizedDiscountType,
              discountValue: _discountValue,
            );

            await PrintService.printWidgetUsingOverlay(context, receiptWidget, width: 220, pixelRatio: 2.0);
            printSuccess = true;
            debugPrint('Print succeeded (overlay method) [offline save].');
          } catch (e, st) {
            debugPrint('Print failed (overlay method) [offline save]: $e\n$st');
          }

          if (!printSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(
                'تم الحفظ محليًا لكن فشلت الطباعة. يمكنك المحاولة لاحقًا.',
                textDirection: TextDirection.rtl,
              )),
            );
          }

          setState(() {
            _cart.clear();
            _paidController.clear();
            _discountValue = 0.0;
            _discountType = 'percent';
            debugPrint("Cart cleared (saved offline), items = ${_cart.length}");
          });

          await _loadTotalProfit();
        } catch (e, st) {
          debugPrint('Failed to save sale locally: $e\n$st');
          throw Exception('فشل التخزين المحلي للفاتورة: $e');
        }
      }
    } catch (e, st) {
      debugPrint('Failed to save sale (client) — error: $e\nstack:\n$st');

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('خطأ أثناء حفظ الفاتورة'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('حسناً'))],
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'فشل حفظ الفاتورة: $e',
          textDirection: TextDirection.rtl,
        )),
      );
    } finally {
      setState(() => _saving = false);
      FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }



  bool _closingShift = false;
  final ApiServiceClose_shieft _apiService = ApiServiceClose_shieft(baseUrl: 'https://nabawisolution.com');
  Future<void> _loadFinancials() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // محاولة online أولًا
      final conn = await Connectivity().checkConnectivity();
      final online = conn != ConnectivityResult.none;

      if (online) {
        try {
          final list = await _service.getLatest(limit: 1);
          if (list.isNotEmpty) {
            final rec = list.first;
            // حدّث الواجهة فوراً
            if (!mounted) return;
            setState(() {
              _startingAmount = rec.startingAmount;
              _cashInWallet = rec.cashInWallet;
            });
            // خزّن محليًا للاستعمال وقت الأوفلاين
            final box = await Hive.openBox('financial_accounts');
            final key = rec.id?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
            await box.put(key, rec.toJsonFull());
            return;
          }
        } catch (e) {
          debugPrint('[Financials] online fetch failed, will fallback to local: $e');
          // fallthrough to local
        }
      }

      // OFFLINE fallback: اقرأ من الـ Hive (listener يحدّث الحالة تلقائياً لكن نقرأ الآن احتياطي)
      await _applyLatestFinancialFromBox();
    } catch (e, st) {
      debugPrint('Failed to load financials: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _confirm_CloseShift() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: const Text('تأكيد عمليه تقفيله الشيفت', style: TextStyle(color: Colors.white)),
          content: const Text('هل أنت متأكد من تاكيد هذه العمليه؟', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
                Session.updateDateTime_end();
              },
              child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );

    if (shouldExit == true && mounted) {
      await _closeShift(); // الآن ننفّذ الإغلاق فعليًا بعد غلق الدايالوج
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }
  Future<void> _loadTotalProfit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profits = await ApiServiceProfit.instance
          .fetchProfitsByCashier(Session.currentUsername?? widget.cashierUsername);

      double sumCash = 0;
      double sumWallet = 0;
      double sumCredit = 0;
      double sumPurchases_paid = 0;
      double sumPurchases_credit = 0;
      double sumWallet_received = 0;
      double sumCash_received = 0;

      for (final p in profits) {
        sumCash += p.total_in_drawer;
        sumWallet += p.total_in_wallet;
        sumCredit += p.cash_with_credit;
        sumPurchases_paid += p.purchases_paid;
        sumPurchases_credit += p.purchases_credit;
        sumWallet_received += p.wallet_received;
        sumCash_received += p.cash_received;
      }

      if (!mounted) return;
      setState(() {
        _totalCash = sumCash;
        _totalWallet = sumWallet;
        _cash_with_credit = sumCredit ;
        _purchases_paid = sumPurchases_paid ;
        _purchases_credit = sumPurchases_credit ;
        _wallet_received = sumWallet_received ;
        _cash_received = sumCash_received ;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }
  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: const Text('تأكيد الخروج',style: TextStyle(color: Colors.white),),
          content: const Text('هل أنت متأكد من الخروج؟',style: TextStyle(color: Colors.white70),),
          actions: [
            TextButton(

              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('تأكيد',style: TextStyle(color: Colors.white),),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء',style: TextStyle(color: Colors.white70),),
            ),

          ],
        ),
      ),
    );

    if (shouldExit == true && mounted) {
      // تذهب إلى LoginScreen وتزيل باقي الشاشة من الستاك
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }
  Future<void> _closeShift() async {
    setState(() => _closingShift = true);
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final fromDateStr = startOfDay.toIso8601String().split('T').first;

      // قيم افتراضية بديلة بدل null لتجنّب Null check operator crash
      final totalCashSafe = _totalCash ?? 0.0;
      final cashReceivedSafe = _cash_received ?? 0.0;
      final walletReceivedSafe = _wallet_received ?? 0.0;
      final purchasesPaidSafe = _purchases_paid ?? 0.0;
      final userStartingSafe = _startingAmount;
      final userNetSalesSafe = _totalCash ?? 0.0;
      final drawerForCashierSafe = _totalWallet ?? 0.0;
      final cardForCashierSafe = (_cashInWallet ?? 0.0) + (_totalWallet ?? 0.0);
      final creditOutstandingSafe = _cash_with_credit ?? 0.0;
      final purchasesCreditSafe = _purchases_credit ?? 0.0;

      // تشخيص سريع: لو البيانات كلها صفر قد يعني أن التحميل فشل
      final anyLoaded = (totalCashSafe + cashReceivedSafe + walletReceivedSafe + userStartingSafe) != 0.0;
      if (!anyLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'لا توجد بيانات كافية لإجراء تقفيل الشيفت — تأكد من تحميل البيانات أو المحاولة بعد التحديث.',
          textDirection: TextDirection.rtl,
        )));
        return;
      }

      final reportWidget = ShiftReportWidget(
        cashierUsername: Session.currentUsername!,
        fromDate: fromDateStr,
        toDate: Session.currentDateTime!,
        totals: {
          'sales_total': totalCashSafe,
          'sales_paid_cash': cashReceivedSafe,
          'sales_paid_card': walletReceivedSafe,
          'purchases_paid': purchasesPaidSafe,
          'user_starting': userStartingSafe,
          'user_net_sales': userNetSalesSafe,
          'drawer_for_cashier': drawerForCashierSafe,
        },
        width: 300,
        drawerCurrent: totalCashSafe,
        cardForCashier: cardForCashierSafe,
        creditOutstandingForCashier: creditOutstandingSafe,
        purchaseReceiptsOutstandingForUser: purchasesCreditSafe,
      );

      // 1) محاولة طباعة التقرير
      try {
        await PrintService.printWidgetUsingOverlay(context, reportWidget, width: 280, pixelRatio: 2.0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'تم طباعة تقرير الشفت لليوم',
          textDirection: TextDirection.rtl,
        )));
      } catch (e, st) {
        debugPrint('Shift print failed: $e\n$st');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'فشل طباعة تقرير الشفت',
          textDirection: TextDirection.rtl,
        )));
      }

      // 2) إرسال start_time إلى السيرفر أو وضعها في الـ queue لو اوفلاين
      try {
        final dynamic startTimeValue = Session.currentDateTime!;
        final dynamic endTimeValue = Session.endDateTime!;
        debugPrint('Sending start_time to server: $startTimeValue');

        final apiResp = await _apiService.closeShift(
          cashierName: Session.currentUsername!,
          startTimeParam: startTimeValue,
          endTime: endTimeValue,
        );

        debugPrint('closeShift API response: success=${apiResp.success}, queued=${apiResp.queued}, message=${apiResp.message}, id=${apiResp.insertId}');

        if (apiResp.success || apiResp.queued) {
          final msg = apiResp.queued
              ? 'تم حفظ تقفيل الشيفت محليًا وسيتم رفعه عند استعادة الاتصال'
              : 'تم حفظ الشفت على السيرفر بنجاح';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, textDirection: TextDirection.rtl)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل حفظ الشفت على السيرفر: ${apiResp.message}', textDirection: TextDirection.rtl),
            backgroundColor: Colors.red[700],
          ));
        }
      } catch (e, st) {
        debugPrint('API closeShift failed: $e\n$st');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء حفظ الشفت: $e', textDirection: TextDirection.rtl)));
      }
    } catch (e, st) {
      debugPrint('Error while closing shift: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تقفيل الشفت: $e', textDirection: TextDirection.rtl)));
    } finally {
      setState(() => _closingShift = false);
    }
  }
  Future<void> _showDiscountDialog() async {
    final options = List.generate(11, (i) => i * 5); // 0,5,10,...,50
    int selected = _discountValue.toInt();
    String discountMode = _discountType; // "percent" or "amount"
    TextEditingController valueController = TextEditingController();

    final res = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: const Center(
                child: Text('اختر نوع الخصم', style: TextStyle(color: Colors.white)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // اختيار نوع الخصم
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(

                          label:Text(
                            "نسبة %",
                            style: TextStyle(
                              fontSize: 17,
                              color: Colors.white,
                            ),
                          ),
                          selected: discountMode == 'percent',
                          onSelected: (_) {
                            setState2(() => discountMode = 'percent');
                          },
                          backgroundColor: AppColorsDark.bgCardColor,
                          selectedColor: AppColorsDark.bgCardColor,
                          checkmarkColor: AppColorsDark.mainColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color:AppColorsDark.bgColor,
                              width: 2,
                            ),
                          )
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                          label:Text(
                            "مبلغ ثابت",
                            style: TextStyle(
                              fontSize: 17,
                              color: Colors.white,
                            ),
                          ),
                          selected: discountMode == 'amount',
                          onSelected: (_) {
                            setState2(() => discountMode = 'amount');
                          },
                          backgroundColor: AppColorsDark.bgCardColor,
                          selectedColor: AppColorsDark.bgCardColor,
                          checkmarkColor: AppColorsDark.mainColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: AppColorsDark.bgColor ,
                              width: 2,
                            ),
                          )
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (discountMode == 'percent')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options.map((v) {
                        final isSelected = v == selected;
                        return ChoiceChip(
                          label: Text('$v%'),
                          selected: isSelected,
                          backgroundColor: AppColorsDark.bgColor,
                          selectedColor: Colors.green,
                          labelStyle: const TextStyle(color: Colors.white),
                          onSelected: (_) {
                            setState2(() => selected = v);
                          },
                        );
                      }).toList(),
                    ),
                  if (discountMode == 'amount')
                    CustomFormField(
                      controller: valueController,
                      hint: "ادخل قيمة الخصم",

                    )
                ],
              ),
              actions: [
                CustomButton(
                  infinity: false,
                  text: 'تطبيق',
                  onPressed: () {
                    if (discountMode == 'amount') {
                      final val = double.tryParse(valueController.text) ?? 0.0;
                      Navigator.of(ctx2).pop({"type": "amount", "value": val});
                    } else {
                      Navigator.of(ctx2).pop({"type": "percent", "value": selected.toDouble()});
                    }
                  },
                ),
                SizedBox(width: 10,),
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () => Navigator.of(ctx2).pop(null),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }),
        );
      },
    );

    if (res != null) {
      setState(() {
        _discountType = res["type"] as String;
        _discountValue = (res["value"] as num).toDouble();
        // لو عندك متغيرات لحسابات الضريبة أو خصومات إضافية - حدثها هنا أيضاً
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _discountType == "percent"
                ? 'تم تطبيق خصم ${_discountValue.toStringAsFixed(0)}% — الإجمالي الآن: ${_effectiveTotal.toStringAsFixed(2)}'
                : 'تم تطبيق خصم بقيمة ${_discountValue.toStringAsFixed(2)} — الإجمالي الآن: ${_effectiveTotal.toStringAsFixed(2)}',
            textDirection: TextDirection.rtl,

          ),
        ),
      );

    }
  }
  Widget _shimmerMoney({double width = 56, double height = 16, BorderRadius? radius}) {
    return Shimmer.fromColors(
      baseColor: Colors.white10,
      highlightColor: Colors.white24,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: radius ?? BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _moneyOrShimmer({double? value, bool withSign = false, bool asInt = true}) {
    if (value == null) {
      return _shimmerMoney(width: 64, height: 16);
    }
    final text = withSign
        ? _formatWithSign(value)
        : NumberFormat("#,###").format(asInt ? value.toInt() : value);
    return Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14));
  }

  @override
  Widget build(BuildContext context) {
    final receiptWidth = 380.0;
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white70),

        leadingWidth: 250,
        toolbarHeight: 65,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
              onPressed: () => _confirmExit(),
            ),
            SizedBox(width: 20,),
            InkWell(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 5,),
                  IconButton(
                    tooltip: "المحفظه الالكترونية",
                    icon: const Icon(Icons.account_balance_wallet,color: Colors.white70,),
                    onPressed: Session.wallet_tx == true ? _openCardWalletDialog:null,
                  ),
                  _moneyOrShimmerWithFlag(value: (_totalWallet ?? 0.0) + (_cashInWallet ?? 0.0))

                ],
              ),
            ),
            SizedBox(width: 20,),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 10,),

                Tooltip(
                  message: "المبلغ الموجود في الدرج",
                  child: SvgPicture.asset(
                    "assets/icons/drawer.svg",
                    color: Colors.white70,
                    width: 25,
                    height: 25,
                  ),
                ),
                SizedBox(height: 10,),
                _moneyOrShimmerWithFlag(value: (_totalCash ?? 0.0) + (_startingAmount ?? 0.0) + _lastOfflineSale, withSign: true)
              ],
            ),
          ],
        ),

        title: Text(
          '${_currentUsername ?? widget.cashierUsername}',
          style: const TextStyle(color: Colors.white, fontSize: 27),
        ),

        actions: [
          Visibility(
            visible: Session.invoice_log,
            child: IconButton(
              tooltip: 'الفواتير السابقة',
              icon: const Icon(Icons.history),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PreviousSalesScreen(
                      cashierUsername: _currentUsername ?? widget.cashierUsername,
                    ),
                  ),
                );
              },
            ),
          ),
          Visibility(
            visible: Session.receive_from_suppliers,
            child: IconButton(
              tooltip: 'استلام بضاعه',
              icon: const Icon(Icons.category),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReceiveFromSupplierScreen()),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'تقفيل الشفت',
            icon: const Icon(Icons.lock_clock),
            onPressed:()=> _closingShift ? null : _confirm_CloseShift(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Focus(
                    focusNode: _inlineKeyboardNode,
                    onKey: (FocusNode node, RawKeyEvent event) {
                      if (event is RawKeyDownEvent) {
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.arrowDown) {
                          setState(() {
                            _inlineSelectedIndex = (_inlineSelectedIndex + 1).clamp(0, _inlineSearchResults.length - 1);
                          });
                          _scrollInlineToIndex(_inlineSelectedIndex);
                          return KeyEventResult.handled;
                        } else if (key == LogicalKeyboardKey.arrowUp) {
                          setState(() {
                            _inlineSelectedIndex = (_inlineSelectedIndex - 1).clamp(0, _inlineSearchResults.length - 1);
                          });
                          _scrollInlineToIndex(_inlineSelectedIndex);
                          return KeyEventResult.handled;
                        } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
                          // <-- التغيير: نتعامل مع Enter فقط لو في نتائج للبحث بالكلمة
                          if (_inlineSearchResults.isNotEmpty) {
                            final idx = _inlineSelectedIndex >= 0 ? _inlineSelectedIndex : 0;
                            if (_dialogOpening) return KeyEventResult.handled;
                            _dialogOpening = true;
                            Future.microtask(() async {
                              try {
                                await _showProductDetailDialog(_inlineSearchResults[idx]);
                              } finally {
                                if (!mounted) return;
                                setState(() {
                                  _inlineSearchResults = [];
                                  _inlineLoading = false;
                                  _inlineSelectedIndex = -1;
                                  _dialogOpening = false;
                                });
                              }
                            });
                            return KeyEventResult.handled;
                          }
                          // لو مفيش نتائج، متقبّضش على Enter هنا علشان يسمح بعمل onSubmitted (الباركود)
                          return KeyEventResult.ignored;
                        } else if (key == LogicalKeyboardKey.escape) {
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                          });
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: CustomFormField(
                        controller: _barcodeController,
                        hint: "امسح الباركود أو اكتب اسم المنتج ثم اضغط Enter",
                        focusNode: _barcodeFocus,
                        onTap: () {
                          // تأكد إن node الخاص بالكيبورد يستلم الفوكس أيضاً عند الضغط في الحقل
                          if (!_inlineKeyboardNode.hasFocus) FocusScope.of(context).requestFocus(_inlineKeyboardNode);
                        },
                        onChanged: (v) {
                          final trimmed = v.trim();
                          final containsLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(trimmed);
                          if (containsLetters) {
                            _scheduleInlineSearch(trimmed);
                          } else {
                            _inlineDebounce?.cancel();
                            setState(() {
                              _inlineSearchResults = [];
                              _inlineLoading = false;
                              _inlineSelectedIndex = -1;
                            });
                          }
                        },
                        onFieldSubmitted:  (v) async {
                          final trimmed = v.trim();
                          if (trimmed.isEmpty) return;

                          final containsLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(trimmed);

                          if (containsLetters) {
                            if (_inlineSearchResults.isNotEmpty) {
                              final first = _inlineSearchResults.first;
                              if (_dialogOpening) return;
                              _dialogOpening = true;
                              try {
                                await _showProductDetailDialog(first);
                              } finally {
                                if (!mounted) return;
                                setState(() {
                                  _inlineSearchResults = [];
                                  _inlineLoading = false;
                                  _inlineSelectedIndex = -1;
                                  _dialogOpening = false;
                                });
                              }
                            } else {
                              await _openNameSearchDialog(initialQuery: trimmed);
                            }
                          } else {
                            // === barcode path: بحث بالباركود وإضافة للسلة ===
                            await _onBarcodeSubmitted(trimmed);

                            // تنظيف الحقل وإرجاع الفوكس للباركود (مريح للكاشير)
                            if (!mounted) return;
                            setState(() {
                              _barcodeController.clear();
                              _inlineSearchResults = [];
                              _inlineSelectedIndex = -1;
                            });
                            FocusScope.of(context).requestFocus(_barcodeFocus);
                          }
                        },
                        keyboardType: TextInputType.text,
                      ),
                    ),
                  ),


                ),
                SizedBox(width: 12),
                CustomButton(
                  text: 'اضافه',
                  onPressed: () => _onBarcodeSubmitted(_barcodeController.text),
                  infinity: false,
                ),

              ],
            ),
            SizedBox(height: 15,),
            // show inline results area
            if (_inlineLoading || _inlineSearchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColorsDark.bgCardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 300),
                child: _inlineLoading
                    ? const Center(child: Text('جاري البحث...', style: TextStyle(color: Colors.white70)))
                    : ListView.separated(
                  controller: _inlineScrollController,
                  shrinkWrap: true,
                  itemCount: _inlineSearchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 0.5, color: Colors.white10),
                  itemBuilder: (context, i) {
                    final item = _inlineSearchResults[i];
                    final name = (item['name'] ?? '').toString();
                    final barcode = (item['barcode'] ?? '').toString();
                    final price = (item['selling_price'] ?? item['sellingPrice'] ?? '').toString();
                    final stock = (item['total_units'] ?? 0).toString();
                    final isSelected = i == _inlineSelectedIndex;

                    return Container(
                      color: isSelected ? Colors.white10 : Colors.transparent,
                      child: ListTile(
                        tileColor: Colors.transparent,
                        title: Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text('باركود: $barcode  •  سعر: $price  •  متاح: $stock',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        onTap: () async {
                          final item = _inlineSearchResults[i];
                          await _showProductDetailDialog(item);
                          if (!mounted) return;
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                          });
                        },

                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? CartListShimmer(
                itemCount: 4, // عدد البطاقات اللي تحب تظهر كـ skeleton
              )
                  : CartList(
                cart: _cart,
                onChangeQty: _changeQuantity,
                onRemove: (pid) => setState(() => _cart.remove(pid)),
                onEditQty: _editQuantityDialog,
              ),
            ),
            const SizedBox(height: 12),
            // Payment controls + discount button row
            Row(
              children: [
                // زر الخصم
                Visibility(
                  visible: Session.discount,
                  child: SizedBox(
                    height: 65,
                    child: ElevatedButton(
                      onPressed: _showDiscountDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _discountValue > 0 ? Colors.orange : AppColorsDark.bgColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_offer, color: Colors.white70,size: 27,),
                          const SizedBox(height: 5),
                          Text(
                            _discountValue > 0 ? '${_discountValue.toStringAsFixed(0)}%' : 'خصم',
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: PaymentControls(
                      paidController: _paidController,
                      addQuickPaid: _addQuickPaid,
                      setQuickPaid: _setQuickPaid,
                      total: _effectiveTotal, // مهم: عرض الإجمالي بعد الخصم
                      saving: _saving,
                      onPayAndSave: () {
                        setState(() {});
                        _saveSale(requireFullPayment: true, paymentMethod: 'cash');
                        Future.microtask(() {
                          _barcodeController.clear();
                          FocusScope.of(context).requestFocus(_barcodeFocus);
                        });
                      },
                      onSaveAsLater: (){
                        _saveSale(requireFullPayment: false, paymentMethod: 'credit');
                        Future.microtask(() {
                          _barcodeController.clear();
                          FocusScope.of(context).requestFocus(_barcodeFocus);
                        });
                      },
                      onSaveAsCard: () {
                        _saveSale(requireFullPayment: true, paymentMethod: 'wallet');
                        Future.microtask(() {
                          _barcodeController.clear();
                          FocusScope.of(context).requestFocus(_barcodeFocus);
                        });
                      },
                      // If you want a BUTTON specifically to pay via the app wallet, you can hook it to:
                      // onSaveAsWallet: () => _saveSale(requireFullPayment: true, paymentMethod: 'wallet'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Offstage(
              offstage: true, // تغيير إلى false للتصحيح ورؤية الإيصال
              child: RepaintBoundary(
                key: _receiptKey,
                child: ReceiptWidget(cart: _cart, paid: _paid, cashierUsername: _currentUsername ?? widget.cashierUsername, width: receiptWidth, useCairo: true),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );

  }

}
