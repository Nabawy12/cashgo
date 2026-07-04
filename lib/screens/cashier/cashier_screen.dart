// lib/screens/cashier/cashier_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:cashgo/models/login.dart';
import 'package:cashgo/services/cashier/close_shieft.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/cart.dart';
import '../../models/product.dart';
import '../../services/Api/Admin/Products.dart';
import '../../services/Api/Admin/financle.dart';
import '../../services/cashier/print.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/cartlist.dart';
import '../../widgets/Cashier/network.dart';
import '../../widgets/Cashier/payment_controller.dart';
import '../../widgets/Cashier/receipt_widget.dart';
import '../../widgets/Loading/cashier/cart.dart';
import '../admin/stock_screen.dart';
import '../shared/login_screen.dart';
import 'ReceiveFromSupplier.dart';
import 'histroy.dart';

// ضع هذه التعاريف أعلى الملف (قبل CashierScreen)
class ArrowDownIntent extends Intent {
  const ArrowDownIntent();
}

class ArrowUpIntent extends Intent {
  const ArrowUpIntent();
}

class EnterIntent extends Intent {
  const EnterIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

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

  int _productIdFromMap(Map<String, dynamic> product) {
    return (product['id'] as num?)?.toInt() ??
        int.tryParse((product['id'] ?? '').toString()) ??
        -1;
  }

  int _totalUnitsFromMap(Map<String, dynamic> product) {
    final explicit = (product['total_units'] as num?)?.toInt();
    if (explicit != null) return explicit;

    final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
    final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
    final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    return cartons * unitsInCarton + remainder;
  }

  int _quantityInCartForProduct({
    int? productId,
    String? barcode,
  }) {
    if (productId != null && productId > 0 && _cart.containsKey(productId)) {
      return _cart[productId]!.quantity;
    }

    final normalizedBarcode = (barcode ?? '').trim();
    if (normalizedBarcode.isEmpty) return 0;

    return _cart.values
        .where((item) => item.product.barcode.trim() == normalizedBarcode)
        .fold<int>(0, (sum, item) => sum + item.quantity);
  }

  int _availableUnitsForProductMap(Map<String, dynamic> product) {
    final totalUnits = _totalUnitsFromMap(product);
    final inCart = _quantityInCartForProduct(
      productId: _productIdFromMap(product),
      barcode: product['barcode']?.toString(),
    );
    return (totalUnits - inCart).clamp(0, totalUnits);
  }

  int _availableUnitsForProduct(Product product) {
    final inCart = _quantityInCartForProduct(
      productId: product.id,
      barcode: product.barcode,
    );
    return (product.totalUnits - inCart).clamp(0, product.totalUnits);
  }

  final GlobalKey _receiptKey = GlobalKey();

  String? _currentUsername; // اسم الكاشير الحقيقي المأخوذ من DB

  double _startingAmount = 0.0;
  double? _drawerBalance;
  bool _drawerBalanceLoaded = false;
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
  bool _inlineSearchPending = false;
  bool _selectFirstWhenInlineReady = false;
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
    final offset = (index * itemHeight)
        .clamp(0.0, _inlineScrollController.position.maxScrollExtent);
    await _inlineScrollController.animateTo(offset,
        duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  void _scheduleInlineSearch(String q) {
    _inlineDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _inlineSearchResults = [];
        _inlineLoading = false;
        _inlineSearchPending = false;
        _selectFirstWhenInlineReady = false;
      });
      return;
    }
    setState(() {
      _inlineSearchPending = true;
    });
    _inlineDebounce =
        Timer(const Duration(milliseconds: 300), () => _runInlineSearch(q));
  }

  Future<void> _runInlineSearch(String q) async {
    setState(() {
      _inlineLoading = true;
      _inlineSearchPending = false;
    });
    var rows = <Map<String, dynamic>>[];
    try {
      rows = await _searchProductsByNameApi(q, limit: 50);
      setState(() {
        _inlineSearchResults = rows;
      });
    } catch (e) {
      debugPrint('inline search (API) error: $e');
      setState(() {
        _inlineSearchResults = [];
      });
    } finally {
      if (!mounted) return;
      final shouldSelectFirst = _selectFirstWhenInlineReady && rows.isNotEmpty;
      setState(() {
        _inlineLoading = false;
        _inlineSearchPending = false;
        _selectFirstWhenInlineReady = false;
      });
      if (shouldSelectFirst) {
        await _openInlineSearchProduct(rows.first);
      }
    }
  }

  Future<void> _openInlineSearchProduct(Map<String, dynamic> product) async {
    if (_dialogOpening) return;
    _dialogOpening = true;
    try {
      await _showProductDetailDialog(product);
    } finally {
      if (!mounted) return;
      setState(() {
        _inlineSearchResults = [];
        _inlineLoading = false;
        _inlineSearchPending = false;
        _selectFirstWhenInlineReady = false;
        _inlineSelectedIndex = -1;
        _dialogOpening = false;
      });
    }
  }

  StreamSubscription<dynamic>? _connSub; // مرن لقبول أي StreamSubscription

  StreamSubscription? _finBoxSub; // استماع لصندوق financial_accounts
  Box? _financialBox; // cache للصندوق المحلي

  // داخل _CashierScreenState

  /// استدعاء مركزي يعيد تشغيل كل الـ inits اللي في initState لديك.
  /// صالح لأن يتحوّل إلى زر Refresh أو يُستدعى عند استعادة الاتصال.
  bool _restartingInit = false;

  Future<void> _restartInitialLoad() async {
    if (_restartingInit) {
      debugPrint('[UI] _restartInitialLoad already running -> skip');
      return;
    }
    _restartingInit = true;
    debugPrint('[UI] _restartInitialLoad starting');

    try {
      // 1) تأكد من إيقاف أي مستمع لصندوق financial قبل إعادة ربطه
      try {
        await _finBoxSub?.cancel();
        _finBoxSub = null;
        debugPrint('[UI] cancelled old _finBoxSub (if any)');
      } catch (e) {
        debugPrint('[UI] failed cancel old finBoxSub: $e');
      }

      // 2) load current user (دالتك async)
      try {
        await _loadCurrentUser();
        debugPrint('[UI] _loadCurrentUser done');
      } catch (e) {
        debugPrint('[UI] _loadCurrentUser failed: $e');
      }

      // 3) wakelock: إعادة التمكين آمنة (idempotent)
      try {
        await WakelockPlus.enable();
        debugPrint('[UI] WakelockPlus.enable done');
      } catch (e) {
        debugPrint('[UI] Wakelock enable failed: $e');
      }

      // 4) re-init financials listener (يفتح الصندوق ويضع listener جديد)
      try {
        await _initFinancialsListener();
        debugPrint('[UI] _initFinancialsListener done');
      } catch (e) {
        debugPrint('[UI] _initFinancialsListener failed: $e');
      }

      // 5) load financials (يحاول السيرفر ثم fallback محلي)
      try {
        await _loadFinancials();
        debugPrint('[UI] _loadFinancials done');
      } catch (e) {
        debugPrint('[UI] _loadFinancials failed: $e');
      }

      // 6) reload local financials then re-try online load (كما في initState)
      try {
        await _loadFinancialsFromLocal();
        await _loadFinancials();
        debugPrint('[UI] _loadFinancialsFromLocal + _loadFinancials done');
      } catch (e) {
        debugPrint('[UI] _loadFinancialsFromLocal/_loadFinancials failed: $e');
      }

      // 8) أخيراً حدث الواجهة
      if (mounted) setState(() {});
      debugPrint('[UI] _restartInitialLoad finished');
    } finally {
      // نسمح بإعادة التشغيل بعد فترة قصيرة لو احتجنا
      Future.delayed(
          const Duration(milliseconds: 200), () => _restartingInit = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocus);
    });
    _loadCurrentUser().then((_) async {
      await _loadFinancialsFromLocal();
      await _loadFinancials();
      await _loadDrawerBalance();
    });
    WakelockPlus.enable();

    // استمع لـ Hive local financials + حاول جلب من السيرفر
    _initFinancialsListener();
    Session.updateDateTime();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldReady = true;
    });

    // init network checker (io/web implementations موجودة عندك)
    _networkCheck = NetworkCheck();

    // فحص أولي لحالة الإنترنت الحقيقية (ما نعرضش سناك بار أثناء التهيئة)
    _checkInitial();

    // استمع لتغيّر واجهة الشبكة (لاحظ أن onConnectivityChanged الآن يعيد List<ConnectivityResult>)
    // فنحوّله إلى عنصر واحد منطقي (أو ConnectivityResult.none لو فاضية)
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .map((list) => (list is List<ConnectivityResult> && list.isNotEmpty)
            ? list.first
            : ConnectivityResult.none)
        .listen((ConnectivityResult result) {
      // لو بدك تحدد سلوك حسب النوع: result == ConnectivityResult.wifi || ethernet ...
      // هنا نعيد فحص الاتصال الحقيقي (socket / http probe) بعد أي تغيير في الواجهة
      _onInterfaceChanged();
    });

    // استمع لبث حالة الإنترنت الحقيقية من NetworkCheck (stream of bool)
    _internetStatusSub = _networkCheck.onStatusChange.listen((connected) {
      _handleConnectionChanged(connected);
    });
  }

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final NetworkCheck _networkCheck;

  // نعمل Subscription على عنصر واحد بعد تحويل القائمة
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<bool>? _internetStatusSub;

  bool _hasInternet = true;
  bool _initialChecked = false;
  bool _isOnline = false;

// لمنع تكرار استدعاءات _onNetworkBack عند تقلبات سريعة
  bool _hasHandledNetworkBack = false;
  // ننتظر أول frame عشان نتأكد إن ScaffoldMessenger جاهز لعرض SnackBars
  bool _scaffoldReady = false;

  Future<void> _checkInitial() async {
    final connected = await _networkCheck.hasConnection();
    _initialChecked = true;
    // لا نعرض SnackBar عند البداية — فقط نحدّث الحالة الداخلية
    _handleConnectionChanged(connected, showSnack: false);
  }

  Future<void> _onInterfaceChanged() async {
    // بعد تغيير الواجهة نعيد الفحص الحقيقي
    final connected = await _networkCheck.hasConnection();
    _handleConnectionChanged(connected);
  }

  void _handleConnectionChanged(bool connected, {bool showSnack = true}) {
    if (!mounted) return;

    // تحديث الـ state المرئي
    if (connected == _hasInternet && showSnack) {
      // لا تغيير مرئي — لكن نحتاج في بعض الأحيان تحديث _isOnline أيضاً
      _isOnline = connected;
      return;
    }

    final wasOnline = _isOnline;
    _isOnline = connected; // <-- هذه القيمة تستخدم لاحقاً في اللوجيك
    setState(() => _hasInternet = connected);

    if (!showSnack) return;

    // تأجيل عرض الـ SnackBar إذا الـ ScaffoldMessenger مش جاهز
    if (!_scaffoldReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack(connected);
      });
    } else {
      _showSnack(connected);
    }

    // --- إذا النت رجع الآن (وكان offline قبل كده) نفّذ مهام المزامنة بأمان ---
    if (connected && !wasOnline) {
      if (!_hasHandledNetworkBack) {
        _hasHandledNetworkBack = true;

        // نأجل شوية عشان نتجنب ارتدادات سريعة
        Future.delayed(const Duration(milliseconds: 300), () async {
          try {
            debugPrint('[networkBack] detected online -> running sync tasks');

            // 1) نفحّص وندفع أي ops معلق (لو عندك SyncManager)
            try {
              await SyncManager.flushOnce();
              debugPrint('[networkBack] SyncManager.flushOnce succeeded');
            } catch (e, st) {
              debugPrint('[networkBack] SyncManager.flushOnce failed: $e\n$st');
            }

            // 2) جلب و مزامنة الـ financials من السيرفر (لو عندك دالة جاهزة)
            try {
              await _fetchAndSyncFinancialsFromServer();
              debugPrint('[networkBack] fetched financials from server');
            } catch (e, st) {
              debugPrint('[networkBack] fetch financials failed: $e\n$st');
            }

            // 3) إعادة تشغيل الـ inits أو إعادة تحميل كل البيانات الحساسية
            try {
              await _restartInitialLoad();
              debugPrint('[networkBack] _restartInitialLoad completed');
            } catch (e, st) {
              debugPrint('[networkBack] _restartInitialLoad failed: $e\n$st');
            }

            // 4) مسح أي مجاميع اوفلاين مخزنة (اختياري حسب منطقك)
            try {
              final meta = await Hive.openBox('meta');
              await meta.put('lastOfflineSale', 0.0);
              await meta.put('lastOfflineSale_cash', 0.0);
              await meta.put('lastOfflineSale_credit', 0.0);

              if (mounted) {
                setState(() {
                  saleOffline_cash = 0.0;
                  saleOffline_credit = 0.0;
                  _lastOfflineSale = 0.0;
                });
              }
              debugPrint('[networkBack] cleared offline meta totals');
            } catch (e, st) {
              debugPrint('[networkBack] clearing offline meta failed: $e\n$st');
            }
          } catch (e, st) {
            debugPrint('[networkBack] unexpected error: $e\n$st');
          } finally {
            // اسمح بإعادة المعالجة بعد ثانيتين لو تقلب النت تاني
            Future.delayed(const Duration(seconds: 2), () {
              _hasHandledNetworkBack = false;
            });
          }
        });
      }
    }
  }

  void _showSnack(bool connected) {
    final messenger = _scaffoldMessengerKey.currentState;
    // إغلاق أي SnackBar سابق
    messenger?.hideCurrentSnackBar();
    if (connected) {
      // استمع لـ Hive local financials + حاول جلب من السيرفر
      _initFinancialsListener();
      _loadFinancials(); // محفوظة لديك — ممكن تبقى مُحدّثة لعمل sync عند online

      _loadFinancialsFromLocal().then((_) => _loadFinancials());
      messenger?.showSnackBar(
        SnackBar(
          content: const Directionality(
            textDirection: TextDirection.rtl,
            child: Text('الإنترنت رجع ✅'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // استمع لـ Hive local financials + حاول جلب من السيرفر
      _initFinancialsListener();
      _loadFinancials(); // محفوظة لديك — ممكن تبقى مُحدّثة لعمل sync عند online

      _loadFinancialsFromLocal().then((_) => _loadFinancials());
      messenger?.showSnackBar(
        SnackBar(
          content: const Directionality(
            textDirection: TextDirection.rtl,
            child: Text('لا يوجد اتصال بالإنترنت ⚠️'),
          ),
          // نتركه ظاهراً لفترة طويلة (سنخفيه تلقائياً عندما يعود)
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: 'إعادة فحص',
            onPressed: () async {
              final connected = await _networkCheck.hasConnection();
              _handleConnectionChanged(connected);
            },
          ),
        ),
      );
    }
  }

// ====================== _initFinancialsListener ======================
  Future<void> _initFinancialsListener() async {
    try {
      _financialBox = await Hive.openBox('financial_accounts');
      // load once immediately (حتى لو الفلتر لاحقاً)
      await _applyLatestFinancialFromBox();

      // ألغِ أي مستمع قديم قبل إنشاء واحد جديد
      await _finBoxSub?.cancel();

      // نراقب التغييرات على الـ box ونطبّق آخر بيانات متاحة
      _finBoxSub = _financialBox!.watch().listen((event) {
        // event قد يحتوي deleted/key/value حسب تغيّر الـ box
        // نقرأ آخر سجل احتياطيًا بدل الاعتماد على event.value مباشرة
        _applyLatestFinancialFromBox();
      });
      debugPrint('[Financials] initFinancialsListener attached');
    } catch (e, st) {
      debugPrint('[Financials] _initFinancialsListener error: $e\n$st');
    }
  }

// ====================== _loadFinancialsFromLocal ======================
  Future<void> _loadFinancialsFromLocal() async {
    try {
      final box = await Hive.openBox('financial_accounts');
      if (box.isEmpty) {
        if (mounted) {
          setState(() {
            _startingAmount = 0.0;
            _financialsLoaded = true;
          });
        }
        return;
      }

      // اختر آخر key بطريقة آمنة (قد لا تكون مرتبة تصاعدياً دائماً لذلك نرتب keys حسب نوعها)
      final keys = box.keys.toList();
      if (keys.isEmpty) {
        if (mounted) {
          setState(() {
            _startingAmount = 0.0;
            _financialsLoaded = true;
          });
        }
        return;
      }

      final lastKey = keys.last;
      final raw = box.get(lastKey);

      // مرونة في التعامل مع أشكال البيانات المختلفة (Map أو JSON string أو كائن)
      Map<String, dynamic> row = {};
      try {
        if (raw is Map) {
          row = Map<String, dynamic>.from(raw);
        } else if (raw is String) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) row = Map<String, dynamic>.from(decoded);
        } else {
          // لو الكائن له toJson أو toMap
          try {
            final candidate = (raw as dynamic).toJson();
            if (candidate is Map) row = Map<String, dynamic>.from(candidate);
          } catch (_) {
            // فشل التحويل — نترك row فارغًا
          }
        }
      } catch (e) {
        debugPrint(
            '[Financials] _loadFinancialsFromLocal parsing raw failed: $e');
      }

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

      final localStart = pickVal(
          ['starting_amount', 'startingAmount', 'start', 'start_amount']);

      if (!mounted) return;
      setState(() {
        _startingAmount = localStart;
        _financialsLoaded = true;
      });
      await DBHelper.instance.setFixedShiftOpeningBalance(localStart);
      await _loadDrawerBalance();
      debugPrint('[Financials] loaded local financials start=$localStart');
    } catch (e, st) {
      debugPrint('Failed to load local financials: $e\n$st');
    }
  }

  bool _financialsLoaded = false;

  Future<void> _applyLatestFinancialFromBox() async {
    try {
      if (!mounted) return;
      if (_financialBox == null || _financialBox!.isEmpty) {
        setState(() {
          _startingAmount = 0.0;
          _financialsLoaded = true; // حتى لو فاضي، نوقف الـ loading
        });
        return;
      }

      final keys = _financialBox!.keys.toList();
      if (keys.isEmpty) {
        setState(() {
          _startingAmount = 0.0;
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

      final localStart = pickVal(
          ['starting_amount', 'startingAmount', 'start', 'start_amount']);

      setState(() {
        _startingAmount = localStart;
        _financialsLoaded = true;
      });
      await DBHelper.instance.setFixedShiftOpeningBalance(localStart);
      await _loadDrawerBalance();
    } catch (e, st) {
      debugPrint('[Financials] _applyLatestFinancialFromBox error: $e\n$st');
      // لو فشل، على الأقل نعرض صفر
      if (mounted) {
        setState(() {
          _startingAmount = 0.0;
          _financialsLoaded = true;
        });
      }
    }
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
      final list =
          await _service.getLatest(limit: 5); // جيب آخر 5 أو 1 حسب رغبتك
      if (list.isEmpty) return;

      // نحول كل FinancialAccount إلى Map ونخزنهم في صندوق financial_accounts
      final box = await Hive.openBox('financial_accounts');
      for (final rec in list) {
        final key = rec.id?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await box.put(key, rec.toJsonFull());
      }

      // بعد التخزين حدّث الحالة من الصندوق (ستلتقطه الـ listener تلقائيًا لكن نضرب تحميل احتياطي)
      await _applyLatestFinancialFromBox();
      debugPrint(
          '[Financials] synced ${list.length} financial records locally');
    } catch (e, st) {
      debugPrint(
          '[Financials] _fetchAndSyncFinancialsFromServer error: $e\n$st');
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
        Session.canViewCredit = cur['can_view_credit'] == 1 ||
            cur['can_view_credit'] == true ||
            cur['can_view_credit']?.toString() == '1' ||
            (cur['permissions'] is Map &&
                ((cur['permissions'] as Map)['can_view_credit'] == true ||
                    (cur['permissions'] as Map)['can_view_credit'] == 1 ||
                    (cur['permissions'] as Map)['can_view_credit']
                            ?.toString() ==
                        '1'));
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
    final args = ModalRoute.of(context)?.settings.arguments;

    String usernameFromArgs = '';
    String roleFromArgs = '';
    bool? canViewCreditFromArgs;

    if (args is Map) {
      usernameFromArgs = (args['username'] ?? '').toString();
      roleFromArgs = (args['role'] ?? '').toString();
      canViewCreditFromArgs = args['can_view_credit'] == true ||
          args['can_view_credit'] == 1 ||
          args['can_view_credit']?.toString() == '1';
    }

    // أفضلية: args > Session > widget prop > ''
    final resolvedUsername = usernameFromArgs.isNotEmpty
        ? usernameFromArgs
        : ((Session.currentUsername ?? '').isNotEmpty
            ? Session.currentUsername
            : (widget.cashierUsername ?? ''));

    final resolvedRole = roleFromArgs.isNotEmpty
        ? roleFromArgs
        : ((Session.currentRole ?? '').isNotEmpty ? Session.currentRole : '');

    setState(() {
      _currentUsername = resolvedUsername;
    });
    if ((resolvedUsername ?? '').isNotEmpty) {
      final activeUsername = resolvedUsername!;
      Session.currentUsername = activeUsername;
      unawaited(DBHelper.instance.ensureCurrentShiftStartDateTime(
        cashierName: activeUsername,
        fallbackStartTime: DateTime.now().toIso8601String(),
      ));
      unawaited(_loadDrawerBalance());
    }

    // ضع Session صراحةً لو احتجت
    Session.currentUsername = resolvedUsername;
    if (resolvedRole!.isNotEmpty) Session.currentRole = resolvedRole;
    if (canViewCreditFromArgs != null) {
      Session.canViewCredit = canViewCreditFromArgs;
    }

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
      // جلب كل المنتجات المطابقة لنفس الباركود لأن بعض الأصناف قد تشترك في نفس الكود.
      final matches = await _getProductsByBarcodeListFromApi(barcode);

      if (matches.isEmpty) {
        if (!mounted) return;
        _showSnackSafe('المنتج غير موجود');
        return;
      }

      final apiProduct = matches.length == 1
          ? matches.first
          : await showProductChoiceDialog(context, matches);
      if (apiProduct == null) return;

      // تحويل إلى نموذج المنتج والتعامل كالسابق
      final product = Product.fromMap(apiProduct);
      final available = _availableUnitsForProduct(product);
      final pid = product.id!;

      if (available <= 0) {
        if (!mounted) return;
        _showSnackSafe('المنتج نفذ من المخزن');
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
      _showSnackSafe('حدث خطأ أثناء التحميل');
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
            title: Center(
                child: Text('اختر المنتج',
                    style: TextStyle(color: AppColorsDark.mainTextDark))),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 0.5),
                itemBuilder: (context, i) {
                  final product = products[i];
                  final name = (product['name'] ?? '').toString();
                  final price = (product['selling_price'] as num?)
                          ?.toDouble()
                          .toStringAsFixed(2) ??
                      double.tryParse(
                              product['selling_price']?.toString() ?? '')
                          ?.toStringAsFixed(2) ??
                      '0.00';
                  final available = _availableUnitsForProductMap(product);
                  return ListTile(
                    title: Text(name,
                        style: TextStyle(
                            color: AppColorsDark.mainTextDark, fontSize: 20)),
                    subtitle: Text(
                      'السعر: $price  •  المتاح: $available',
                      style: TextStyle(color: AppColorsDark.mainTextLight),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(product);
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
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double get _total => computeTotal(_cart);
  double get _paid =>
      double.tryParse(_paidController.text.replaceAll(',', '')) ?? 0.0;

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
  Future<List<Map<String, dynamic>>> _getProductsByBarcodeListFromApi(
      String barcode) async {
    try {
      final all = await ProductApi.getAllProducts();
      final code = barcode.trim();
      if (code.isEmpty) return [];
      final matches = all
          .where((p) => (p['barcode']?.toString() ?? '').trim() == code)
          .toList();
      return matches;
    } catch (e) {
      debugPrint('API barcode list error: $e');
      return [];
    }
  }

  /// جلب منتج واحد من الـ API بالباركود (ترجع null لو مفيش)
  Future<Map<String, dynamic>?> _getProductByBarcodeFromApi(
      String barcode) async {
    try {
      return await ProductApi.getProductByBarcode(barcode.trim());
    } catch (e) {
      debugPrint('API get product by barcode error: $e');
      return null;
    }
  }

  /// بحث بالاسم عبر الـ API:
  /// ملاحظة: لو الـ API يدعم بحث سيرفر-side من الأفضل استدعاؤه مباشرة — هنا نعمل جلب لكل المنتجات ثم نفلتر محلياً.
  Future<List<Map<String, dynamic>>> _searchProductsByNameApi(String q,
      {int limit = 50}) async {
    try {
      final all = await ProductApi.getAllProducts();
      final needle = q.trim().toLowerCase();
      if (needle.isEmpty) return [];
      final results = all
          .where((p) {
            final name = (p['name'] ?? '').toString().toLowerCase();
            return name.contains(needle);
          })
          .take(limit)
          .toList();
      return results;
    } catch (e) {
      debugPrint('API search by name error: $e');
      return [];
    }
  }

  void _changeQuantity(int productId, int newQty) async {
    if (!_cart.containsKey(productId)) return;
    final productMap = await ProductApi.getProductByBarcode(
        (_cart[productId]!.product.barcode));
    if (productMap == null) return;
    final product = Product.fromMap(productMap);
    final currentQty = _cart[productId]!.quantity;
    final available = _availableUnitsForProduct(product) + currentQty;
    if (newQty <= 0) {
      setState(() => _cart.remove(productId));
    } else if (newQty > available) {
      _showSnackSafe('المنتج نفذ من المخزن');
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
        backgroundColor: AppColorsDark.bgCardColor,
        title: Text(
          'تعديل الكمية',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColorsDark.mainTextDark),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColorsDark.mainTextDark),
          cursorColor: AppColorsDark.mainColor,
          decoration: InputDecoration(
            hintText: 'ادخل الكمية (قطع)',
            hintTextDirection: TextDirection.rtl,
            hintStyle:
                TextStyle(color: AppColorsDark.mainTextDark.withAlpha(150)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColorsDark.strokColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColorsDark.mainColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.black
                  : Colors.white,
              backgroundColor: AppColorsDark.bgColor,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColorsDark.mainColor,
              foregroundColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.black
                  : Colors.white,
            ),
            onPressed: () {
              final v = int.tryParse(controller.text) ?? current;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('موافق'),
          ),
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
          title: Center(
              child: Text('اسم العميل للفاتورة الآجلة',
                  style: TextStyle(color: AppColorsDark.mainTextDark))),
          content: CustomFormField(
            controller: controller,
            hint: 'اكتب اسم العميل أو الجهة',
          ),
          actions: [
            TextButton(
              style:
                  TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
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

  Future<void> _loadDrawerBalance() async {
    final username =
        Session.currentUsername ?? _currentUsername ?? widget.cashierUsername;
    try {
      final balance =
          await DBHelper.instance.computeCurrentShiftDrawerBalance(username);
      if (!mounted) return;
      setState(() {
        _drawerBalance = balance;
        _drawerBalanceLoaded = true;
      });
    } catch (e, st) {
      debugPrint('Failed to load drawer balance: $e\n$st');
      if (!mounted) return;
      setState(() {
        _drawerBalance = 0.0;
        _drawerBalanceLoaded = true;
      });
    }
  }

  String _formatSimpleMoney(double value) {
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
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
                final rows =
                    await DBHelper.instance.searchProductsByName(q, limit: 50);
                setState2(() {
                  results = rows;
                  selectedIndex = results.isNotEmpty ? 0 : -1;
                });
              } catch (e) {
                debugPrint('searchProductsByName error: $e');
                setState2(() {
                  results = [];
                  selectedIndex = -1;
                });
              } finally {
                setState2(() => loading = false);
              }
            }

            void scheduleSearch(String q) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () {
                if (q.trim().isNotEmpty)
                  runSearch(q);
                else
                  setState2(() {
                    results = [];
                    selectedIndex = -1;
                  });
              });
            }

            void ensureSelectedVisible() {
              if (!scrollController.hasClients || selectedIndex < 0) return;
              const itemHeight = 72.0;
              final offset = (selectedIndex * itemHeight)
                  .clamp(0.0, scrollController.position.maxScrollExtent);
              scrollController.animateTo(offset,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut);
            }

            void _ensureKeyFocusAndUnfocusTextIfNeeded() {
              if (textFocus.hasFocus) {
                try {
                  textFocus.unfocus();
                } catch (_) {}
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
                  if (!textFocus.hasFocus)
                    FocusScope.of(ctx2).requestFocus(textFocus);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColorsDark.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColorsDark.strokColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          customInputText.isEmpty
                              ? 'اكتب اسم المنتج...'
                              : customInputText,
                          style: TextStyle(
                            color: customInputText.isEmpty
                                ? AppColorsDark.mainTextLight
                                : AppColorsDark.mainTextDark,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (loading)
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator())
                      else if (customInputText.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close,
                              color: Theme.of(context).iconTheme.color),
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
                LogicalKeySet(LogicalKeyboardKey.arrowDown):
                    const ArrowDownIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowUp):
                    const ArrowUpIntent(),
                LogicalKeySet(LogicalKeyboardKey.enter): const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.numpadEnter):
                    const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ArrowDownIntent:
                      CallbackAction<ArrowDownIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex =
                            (selectedIndex + 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  ArrowUpIntent:
                      CallbackAction<ArrowUpIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex =
                            (selectedIndex - 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  EnterIntent: CallbackAction<EnterIntent>(onInvoke: (intent) {
                    if (selectedIndex >= 0 && selectedIndex < results.length) {
                      final item = results[selectedIndex];
                      Future.microtask(() => _openInlineSearchProduct(item));
                    }
                    return null;
                  }),
                  EscapeIntent:
                      CallbackAction<EscapeIntent>(onInvoke: (intent) {
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
                      if (char.isNotEmpty &&
                          char.codeUnitAt(0) != 10 &&
                          !event.isControlPressed &&
                          !event.isMetaPressed) {
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
                            customInputText = customInputText.substring(
                                0, customInputText.length - 1);
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

                      if (key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.numpadEnter) {
                        if (selectedIndex >= 0 &&
                            selectedIndex < results.length) {
                          final item = results[selectedIndex];
                          Future.microtask(
                              () => _openInlineSearchProduct(item));
                        }
                        return;
                      }

                      if (key == LogicalKeyboardKey.escape) {
                        Navigator.of(ctx2).pop();
                        return;
                      }

                      // arrows: نحول الفوكس إلى keyFocus لأننا نريد أنها تستخدم لتنقّل النتائج
                      if (key == LogicalKeyboardKey.arrowDown ||
                          key == LogicalKeyboardKey.arrowUp) {
                        // ننقل الفوكس لالتقاط الأسهم في المكان اللي يتعامل مع التنقّل (keyFocus موجود في الـ dialog)
                        if (!keyFocus.hasFocus)
                          FocusScope.of(ctx2).requestFocus(keyFocus);

                        // وإذا أردتي يمكن هنا أيضًا التحكم المباشر بتغيير selectedIndex
                        if (results.isNotEmpty) {
                          setState2(() {
                            if (key == LogicalKeyboardKey.arrowDown) {
                              selectedIndex = (selectedIndex + 1)
                                  .clamp(0, results.length - 1);
                            } else {
                              selectedIndex = (selectedIndex - 1)
                                  .clamp(0, results.length - 1);
                            }
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            // scroll to selected
                            const itemHeight = 72.0;
                            if (scrollController.hasClients &&
                                selectedIndex >= 0) {
                              final offset = (selectedIndex * itemHeight).clamp(
                                  0.0,
                                  scrollController.position.maxScrollExtent);
                              scrollController.animateTo(offset,
                                  duration: const Duration(milliseconds: 150),
                                  curve: Curves.easeInOut);
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
        final available = _availableUnitsForProductMap(product);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            final name = (product['name'] ?? '').toString();
            final price =
                (product['selling_price'] ?? product['sellingPrice'] ?? 0.0);
            final desc = (product['description'] ?? '').toString();

            // extracted add-to-cart logic so we can call it from button and onSubmitted
            Future<void> addRequested() async {
              final pid = (product['id'] as num?)?.toInt();
              if (pid == null) {
                if (mounted) _showSnackSafe('المنتج غير صالح');
                return;
              }
              final requested =
                  qty <= 0 ? 1 : qty; // default 1 if empty or zero
              if (requested > available) {
                if (mounted) _showSnackSafe('المنتج نفذ من المخزن');
                return;
              }

              // Update outer state (the cart)
              if (mounted) {
                setState(() {
                  if (_cart.containsKey(pid)) {
                    _cart[pid]!.quantity += requested;
                  } else {
                    final prodModel = Product.fromMap(product);
                    _cart[pid] =
                        CartItem(product: prodModel, quantity: requested);
                  }
                });
              }

              // close dialog and give feedback
              Navigator.of(ctx2).pop();
              if (mounted) {
                _showSnackSafe(
                    'تمت إضافة $requested قطعة من ${product['name']}');
                _barcodeController.clear();
                FocusScope.of(context).requestFocus(_barcodeFocus);
              }
            }

            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Text(name,
                  style: TextStyle(color: AppColorsDark.mainTextDark)),
              content: SingleChildScrollView(
                // prevents overflow when keyboard opens
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (desc.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(desc,
                              style:
                                  TextStyle(color: AppColorsDark.mainTextLight),
                              textAlign: TextAlign.right),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('السعر: ${price.toString()}',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextLight)),
                          Text('متاح: $available',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextLight)),
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
                                        selection: TextSelection.collapsed(
                                            offset: qty.toString().length),
                                      );
                                    });
                                  }
                                : null,
                            icon: Icon(Icons.remove_circle_outline,
                                color: Theme.of(context).iconTheme.color),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColorsDark.bgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: TextField(
                              controller: qtyController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontSize: 18),
                              decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero),
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
                                        selection: TextSelection.collapsed(
                                            offset: qty.toString().length),
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
                                        selection: TextSelection.collapsed(
                                            offset: qty.toString().length),
                                      );
                                    });
                                  }
                                : null,
                            icon: Icon(Icons.add_circle_outline,
                                color: Theme.of(context).iconTheme.color),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                      backgroundColor: AppColorsDark.bgColor),
                  onPressed: () {
                    Navigator.of(ctx2).pop();
                    Future.microtask(() {
                      _barcodeController.clear();
                      FocusScope.of(context).requestFocus(_barcodeFocus);
                    });
                  },
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
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
  final InsertFinancialAccountService _service =
      InsertFinancialAccountService();

// UUID للـ sales ops
  final _uuidForSale = Uuid();

  double _lastOfflineSale = 0.0; // <-- ضيف هذا السطر هنا جنب _totalCash

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

  double saleOffline_cash = 0.0;
  double saleOffline_credit = 0.0;

  Future<void> _saveSale(
      {required bool requireFullPayment, String paymentMethod = 'cash'}) async {
    if (_cart.isEmpty) return;
    if (_saving) return;

    Future<void> recordSaleTotals(double amount, String pm) async {
      final meta = await Hive.openBox('meta');
      double cash = (meta.get('lastOfflineSale_cash') as num? ?? 0).toDouble();
      double credit =
          (meta.get('lastOfflineSale_credit') as num? ?? 0).toDouble();
      final p = pm.toLowerCase();
      if (p == 'cash')
        cash += amount;
      else if (p == 'credit')
        credit += amount;
      else if (p != 'wallet' && p != 'card') cash += amount;
      await meta.put('lastOfflineSale_cash', cash);
      await meta.put('lastOfflineSale_credit', credit);
      await meta.put('lastOfflineSale', cash);
      if (mounted) {
        setState(() {
          saleOffline_cash = cash;
          saleOffline_credit = credit;
          _lastOfflineSale = cash;
        });
      }
    }

    final subtotal = _total;
    final normalizedDiscountType =
        (_discountType == 'amount') ? 'fixed' : _discountType;
    double discountAmount = 0.0;
    if (normalizedDiscountType == 'percent' && _discountValue > 0) {
      discountAmount = subtotal * (_discountValue.clamp(0.0, 100.0) / 100.0);
    } else if (normalizedDiscountType == 'fixed' && _discountValue > 0) {
      discountAmount = _discountValue > subtotal ? subtotal : _discountValue;
    }
    final total = (subtotal - discountAmount).clamp(0.0, double.infinity);

    if (mounted) setState(() => _saving = true);

    try {
      String? customerName;
      if (paymentMethod == 'credit') {
        customerName = await _askForCustomerName();
        if (customerName == null || customerName.isEmpty) {
          _showSnackSafe(
              'تم إلغاء حفظ الفاتورة: يجب إدخال اسم العميل للفواتير الآجلة');
          return;
        }
      }

      final paid = (paymentMethod == 'card' || paymentMethod == 'wallet')
          ? total
          : _paid;
      if (requireFullPayment && paid < total) {
        _showSnackSafe('العميل لم يدفع كامل المبلغ');
        return;
      }

      final cashierNameToUse =
          Session.currentUsername ?? widget.cashierUsername;
      final cartPayload = <Map<String, dynamic>>[];
      _cart.forEach((productId, cartItem) {
        cartPayload.add({
          'product_id': productId,
          'barcode': cartItem.product.barcode ?? '',
          'name': cartItem.product.name ?? '',
          'price': cartItem.product.sellingPrice,
          'qty': cartItem.quantity,
        });
      });

      final saleId = await DBHelper.instance.createSaleWithItems(
        items: cartPayload,
        subtotal: subtotal,
        total: total,
        paid: paid,
        cashierUsername: cashierNameToUse,
        paymentMethod: paymentMethod,
        requireFullPayment: requireFullPayment,
        customerName: customerName,
        discountType: normalizedDiscountType,
        discountValue: _discountValue,
      );
      debugPrint('[saveSale] saved locally with saleId=$saleId');

      await recordSaleTotals(total, paymentMethod);
      await _loadDrawerBalance();

      if (mounted) {
        setState(() {
          _cart.clear();
          _paidController.clear();
          _discountValue = 0.0;
          _discountType = 'percent';
          _saving = false;
        });
        FocusScope.of(context).requestFocus(_barcodeFocus);
      }
      _showSnackSafe('تم الحفظ بنجاح');
    } catch (e, st) {
      debugPrint('Failed to save sale locally: $e\n$st');
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('خطأ أثناء حفظ الفاتورة'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('حسناً'))
            ],
          ),
        );
      }
      _showSnackSafe('فشل حفظ الفاتورة: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
      if (mounted) FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }

  void _showSnackSafe(String message,
      {Duration duration = const Duration(seconds: 3),
      SnackBarAction? action}) {
    _showSnackBarSafe(SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text(message),
      ),
      duration: duration,
      action: action,
    ));
  }

  void _showSnackBarSafe(SnackBar snack) {
    // نؤجّل العرض لآخر frame عشان نتأكد إن الـ Scaffold مسجّل فعلاً
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(snack);
        return;
      }
      debugPrint(
          '[showSnackSafe] cannot show snack: ScaffoldMessenger not ready');
    });
  }

  bool _closingShift = false;
  final ApiServiceClose_shieft _apiService = ApiServiceClose_shieft();
// ====================== _loadFinancials ======================
  Future<void> _loadFinancials({bool forceOnlineCheck = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // 1) قرار سريع: نثق أولاً في الحالة المركزية _isOnline
      bool online = _isOnline;

      // 2) إذا لم نكن واثقين أو طُلب فحص إجباري، نتحقق سريعاً:
      if (!online || forceOnlineCheck) {
        // فحص واجهة الشبكة (WiFi/ethernet/mobile) أولاً — أسرع من probe
        final conn = await Connectivity().checkConnectivity();
        if (conn != ConnectivityResult.none) {
          // نفعل probe حقيقي لكن لا ننتظر أكثر من ثانيتين لتقليل الـ UX delay
          try {
            online = await _networkCheck
                .hasConnection()
                .timeout(const Duration(seconds: 2));
          } catch (_) {
            online = false;
          }
        } else {
          online = false;
        }
        debugPrint(
            '[Financials] connectivity check -> conn=$conn, probeOnline=$online');
      }

      // 3) لو عندنا إنترنت حقيقي، حاول تجيب من السيرفر أولاً
      if (online) {
        try {
          // timeout معقول للـ API
          final list = await _service
              .getLatest(limit: 1)
              .timeout(const Duration(seconds: 8));
          if (list.isNotEmpty) {
            final rec = list.first;
            // خزّن/حدّث الـ Hive بحذر ثم عمل setState
            try {
              final box = await Hive.openBox('financial_accounts');
              final key = rec.id?.toString() ??
                  DateTime.now().millisecondsSinceEpoch.toString();
              await box.put(key, rec.toJsonFull());
              debugPrint('[Financials] saved server record to Hive key=$key');
            } catch (e, st) {
              debugPrint(
                  '[Financials] failed to save server record to Hive: $e\n$st');
            }

            if (!mounted) return;
            setState(() {
              _startingAmount = rec.startingAmount;
              _financialsLoaded = true;
            });
            await DBHelper.instance
                .setFixedShiftOpeningBalance(rec.startingAmount);
            await _loadDrawerBalance();
            return;
          } else {
            debugPrint('[Financials] server returned empty list');
          }
        } catch (e, st) {
          debugPrint(
              '[Financials] online fetch failed despite online=true: $e\n$st');
          // fallthrough to local
        }
      } else {
        debugPrint('[Financials] not online -> fallback to local');
      }

      // 4) OFFLINE fallback: اقرأ من الـ Hive (listener يتابع التغييرات)
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
          title: Text('تأكيد عمليه تقفيله الشيفت',
              style: TextStyle(color: AppColorsDark.mainTextDark)),
          content: Text('هل أنت متأكد من تاكيد هذه العمليه؟',
              style: TextStyle(color: AppColorsDark.mainTextLight)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                'تأكيد',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (shouldExit == true && mounted) {
      debugPrint('[CloseShiftUI] close shift confirmed, starting close flow');
      final success = await _closeShift();
      if (!mounted) return;
      debugPrint('[CloseShiftUI] close shift finished success=$success');
      if (!success) {
        debugPrint(
            '[CloseShiftUI] close shift failed, staying on cashier screen');
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: Text(
            'تأكيد الخروج',
            style: TextStyle(color: AppColorsDark.mainTextDark),
          ),
          content: Text(
            'هل أنت متأكد من الخروج؟',
            style: TextStyle(color: AppColorsDark.mainTextLight),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'تأكيد',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
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

  Future<bool> _closeShift() async {
    debugPrint('[CloseShiftUI] _closeShift entered');
    setState(() => _closingShift = true);
    try {
      if (Session.currentDateTime == null) {
        Session.updateDateTime();
        debugPrint(
            '[CloseShiftUI] Session.currentDateTime was null, set to ${Session.currentDateTime}');
      }
      Session.updateDateTime_end(); // always capture NOW as end time
      debugPrint(
          '[CloseShiftUI] Session.endDateTime captured now as ${Session.endDateTime}');

      final cashierName = Session.currentUsername ?? '';
      if (cashierName.trim().isEmpty) {
        throw 'لا يوجد كاشير مسجل للدخول';
      }

      final dynamic startTimeValue = Session.currentDateTime!;
      final dynamic endTimeValue = Session.endDateTime!;
      debugPrint(
          '[CloseShiftUI] calling closeShift cashier=$cashierName start=$startTimeValue end=$endTimeValue');
      final apiResp = await _apiService.closeShift(
        cashierName: cashierName,
        startTimeParam: startTimeValue,
        endTime: endTimeValue,
      );

      debugPrint(
          'closeShift local response: success=${apiResp.success}, message=${apiResp.message}, id=${apiResp.insertId}');

      if (!apiResp.success && !apiResp.queued) {
        _showSnackBarSafe(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('فشل حفظ تقفيل الشيفت: ${apiResp.message}'),
          ),
          backgroundColor: Colors.red[700],
        ));
        debugPrint(
            '[CloseShiftUI] closeShift response failed, returning false');
        return false;
      }

      if (mounted) {
        setState(() {
          _startingAmount = apiResp.openingBalance;
          _drawerBalance = apiResp.openingBalance;
          _drawerBalanceLoaded = true;
        });
      }

      _showSnackBarSafe(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('تم حفظ تقفيل الشيفت محليًا'),
        ),
      ));
      debugPrint(
          '[CloseShiftUI] close shift saved id=${apiResp.insertId} totalSales=${apiResp.totalSales} closingBalance=${apiResp.closingBalance}');
      return true;
    } catch (e, st) {
      debugPrint('Error while closing shift: $e\n$st');
      _showSnackBarSafe(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل تقفيل الشفت: $e'),
        ),
      ));
      return false;
    } finally {
      if (mounted) setState(() => _closingShift = false);
      debugPrint('[CloseShiftUI] _closeShift finished');
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
              title: Center(
                child: Text('اختر نوع الخصم',
                    style: TextStyle(color: AppColorsDark.mainTextDark)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // اختيار نوع الخصم
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                          label: Text(
                            "نسبة %",
                            style: TextStyle(
                              fontSize: 17,
                              color: AppColorsDark.mainTextDark,
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
                              color: AppColorsDark.bgColor,
                              width: 2,
                            ),
                          )),
                      const SizedBox(width: 8),
                      ChoiceChip(
                          label: Text(
                            "مبلغ ثابت",
                            style: TextStyle(
                              fontSize: 17,
                              color: AppColorsDark.mainTextDark,
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
                              color: AppColorsDark.bgColor,
                              width: 2,
                            ),
                          )),
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
                          labelStyle:
                              TextStyle(color: AppColorsDark.mainTextDark),
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
                      Navigator.of(ctx2).pop(
                          {"type": "percent", "value": selected.toDouble()});
                    }
                  },
                ),
                SizedBox(
                  width: 10,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      backgroundColor: AppColorsDark.bgColor),
                  onPressed: () => Navigator.of(ctx2).pop(null),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
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

      _showSnackSafe(
        _discountType == "percent"
            ? 'تم تطبيق خصم ${_discountValue.toStringAsFixed(0)}% — الإجمالي الآن: ${_effectiveTotal.toStringAsFixed(2)}'
            : 'تم تطبيق خصم بقيمة ${_discountValue.toStringAsFixed(2)} — الإجمالي الآن: ${_effectiveTotal.toStringAsFixed(2)}',
      );
    }
  }


  Widget _appBarAction(IconData icon, String label, VoidCallback? onPressed,
      {Color? color}) {
    final c = color ?? Theme.of(context).iconTheme.color!;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onPressed == null ? c.withOpacity(0.3) : c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: onPressed == null ? c.withOpacity(0.3) : c,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptWidth = 380.0;
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        backgroundColor: AppColorsDark.bgColor,
        appBar: AppBar(
          backgroundColor: AppColorsDark.bgCardColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          toolbarHeight: 60,
          leadingWidth: 160,
          leading: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    color: Theme.of(context).iconTheme.color, size: 18),
                onPressed: _confirmExit,
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      color: _drawerBalanceLoaded
                          ? Colors.greenAccent
                          : AppColorsDark.mainTextLight,
                      size: 18),
                  const SizedBox(height: 2),
                  Text(
                    _drawerBalanceLoaded
                        ? _formatSimpleMoney(_drawerBalance ?? 0.0)
                        : '...',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الكاشير',
                  style: TextStyle(
                      color: AppColorsDark.mainTextDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text(
                _currentUsername ?? widget.cashierUsername,
                style: TextStyle(
                    color: AppColorsDark.mainColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Session.invoice_log)
                    _appBarAction(Icons.history_rounded, 'الفواتير', () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PreviousSalesScreen(
                          cashierUsername: _currentUsername ?? widget.cashierUsername,
                          canViewCreditInvoices: Session.canViewCredit,
                        ),
                      ));
                    }),
                  if (Session.canViewCredit)
                    _appBarAction(Icons.receipt_long_rounded, 'آجل', () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CreditsScreen()));
                    }),
                  if (Session.receive_from_suppliers)
                    _appBarAction(Icons.inventory_2_rounded, 'بضاعة', () {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ReceiveFromSupplierScreen()));
                    }),
                  _appBarAction(
                    Icons.lock_clock_rounded,
                    'تقفيل',
                    _closingShift ? null : _confirm_CloseShift,
                    color: Colors.orangeAccent,
                  ),
                ],
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Focus(
                      focusNode: _inlineKeyboardNode,
                      onKey: (FocusNode node, RawKeyEvent event) {
                        if (event is RawKeyDownEvent) {
                          final key = event.logicalKey;
                          if (key == LogicalKeyboardKey.arrowDown) {
                            setState(() {
                              _inlineSelectedIndex = (_inlineSelectedIndex + 1)
                                  .clamp(0, _inlineSearchResults.length - 1);
                            });
                            _scrollInlineToIndex(_inlineSelectedIndex);
                            return KeyEventResult.handled;
                          } else if (key == LogicalKeyboardKey.arrowUp) {
                            setState(() {
                              _inlineSelectedIndex = (_inlineSelectedIndex - 1)
                                  .clamp(0, _inlineSearchResults.length - 1);
                            });
                            _scrollInlineToIndex(_inlineSelectedIndex);
                            return KeyEventResult.handled;
                          } else if (key == LogicalKeyboardKey.enter ||
                              key == LogicalKeyboardKey.numpadEnter) {
                            if (_inlineLoading || _inlineSearchPending) {
                              setState(() {
                                _selectFirstWhenInlineReady = true;
                              });
                              return KeyEventResult.handled;
                            }

                            if (_inlineSearchResults.isNotEmpty) {
                              final idx = _inlineSelectedIndex >= 0
                                  ? _inlineSelectedIndex
                                  : 0;
                              Future.microtask(() => _openInlineSearchProduct(
                                  _inlineSearchResults[idx]));
                              return KeyEventResult.handled;
                            }

                            final trimmed = _barcodeController.text.trim();
                            final containsLetters =
                                RegExp(r'[A-Za-z\u0621-\u064A]')
                                    .hasMatch(trimmed);
                            if (containsLetters) {
                              return KeyEventResult.handled;
                            }

                            return KeyEventResult.ignored;
                          } else if (key == LogicalKeyboardKey.escape) {
                            setState(() {
                              _inlineSearchResults = [];
                              _inlineLoading = false;
                              _inlineSearchPending = false;
                              _selectFirstWhenInlineReady = false;
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
                          hint:
                              "امسح الباركود أو اكتب اسم المنتج ثم اضغط إدخال",
                          focusNode: _barcodeFocus,
                          onTap: () {
                            // تأكد إن node الخاص بالكيبورد يستلم الفوكس أيضاً عند الضغط في الحقل
                            if (!_inlineKeyboardNode.hasFocus)
                              FocusScope.of(context)
                                  .requestFocus(_inlineKeyboardNode);
                          },
                          onChanged: (v) {
                            final trimmed = v.trim();
                            final containsLetters =
                                RegExp(r'[A-Za-z\u0621-\u064A]')
                                    .hasMatch(trimmed);
                            if (containsLetters) {
                              _scheduleInlineSearch(trimmed);
                            } else {
                              _inlineDebounce?.cancel();
                              setState(() {
                                _inlineSearchResults = [];
                                _inlineLoading = false;
                                _inlineSearchPending = false;
                                _selectFirstWhenInlineReady = false;
                                _inlineSelectedIndex = -1;
                              });
                            }
                          },
                          onFieldSubmitted: (v) async {
                            final trimmed = v.trim();
                            if (trimmed.isEmpty) return;

                            final containsLetters =
                                RegExp(r'[A-Za-z\u0621-\u064A]')
                                    .hasMatch(trimmed);

                            if (containsLetters) {
                              if (_inlineLoading || _inlineSearchPending) {
                                setState(() {
                                  _selectFirstWhenInlineReady = true;
                                });
                              } else if (_inlineSearchResults.isNotEmpty) {
                                await _openInlineSearchProduct(
                                    _inlineSearchResults.first);
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
                              FocusScope.of(context)
                                  .requestFocus(_barcodeFocus);
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
                    onPressed: () =>
                        _onBarcodeSubmitted(_barcodeController.text),
                    infinity: false,
                  ),
                ],
              ),
              SizedBox(
                height: 15,
              ),
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
                      ? Center(
                          child: Text('جاري البحث...',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextLight)))
                      : ListView.separated(
                          controller: _inlineScrollController,
                          shrinkWrap: true,
                          itemCount: _inlineSearchResults.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 0.5, color: AppColorsDark.strokColor),
                          itemBuilder: (context, i) {
                            final item = _inlineSearchResults[i];
                            final name = (item['name'] ?? '').toString();
                            final barcode = (item['barcode'] ?? '').toString();
                            final price = (item['selling_price'] ??
                                    item['sellingPrice'] ??
                                    '')
                                .toString();
                            final stock =
                                _availableUnitsForProductMap(item).toString();
                            final isSelected = i == _inlineSelectedIndex;

                            return Container(
                              color: isSelected
                                  ? AppColorsDark.mainColor
                                      .withValues(alpha: 0.08)
                                  : Colors.transparent,
                              child: ListTile(
                                tileColor: Colors.transparent,
                                title: Text(name,
                                    style: TextStyle(
                                        color: isSelected
                                            ? AppColorsDark.mainTextDark
                                            : AppColorsDark.mainTextDark,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                subtitle: Text(
                                    'باركود: $barcode  •  سعر: $price  •  متاح: $stock',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextLight,
                                        fontSize: 12)),
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
              Flexible(
                fit: FlexFit.tight,
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
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Visibility(
                      visible: Session.discount,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                            start: 8, end: 14, bottom: 6),
                        child: SizedBox(
                          height: 72,
                          child: ElevatedButton(
                            onPressed: _showDiscountDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _discountValue > 0
                                  ? Colors.orange
                                  : AppColorsDark.bgColor,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_offer,
                                  color: Theme.of(context).iconTheme.color,
                                  size: 27,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _discountValue > 0
                                      ? '${_discountValue.toStringAsFixed(0)}%'
                                      : 'خصم',
                                  style: TextStyle(
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: PaymentControls(
                          paidController: _paidController,
                          addQuickPaid: _addQuickPaid,
                          setQuickPaid: _setQuickPaid,
                          total: _effectiveTotal,
                          saving: _saving,
                          onPayAndSave: () async {
                            setState(() {});
                            await _saveSale(
                                requireFullPayment: true,
                                paymentMethod: 'cash');
                            Future.microtask(() {
                              _barcodeController.clear();
                              FocusScope.of(context)
                                  .requestFocus(_barcodeFocus);
                            });
                          },
                          onSaveAsLater: () async {
                            await _saveSale(
                                requireFullPayment: false,
                                paymentMethod: 'credit');
                            Future.microtask(() {
                              _barcodeController.clear();
                              FocusScope.of(context)
                                  .requestFocus(_barcodeFocus);
                            });
                          },
                          onSaveAsCard: () async {
                            await _saveSale(
                                requireFullPayment: true,
                                paymentMethod: 'wallet');
                            Future.microtask(() {
                              _barcodeController.clear();
                              FocusScope.of(context)
                                  .requestFocus(_barcodeFocus);
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Offstage(
                offstage: true, // تغيير إلى false للتصحيح ورؤية الإيصال
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: ReceiptWidget(
                      cart: _cart,
                      paid: _paid,
                      cashierUsername:
                          _currentUsername ?? widget.cashierUsername,
                      width: receiptWidth,
                      useCairo: true),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}
