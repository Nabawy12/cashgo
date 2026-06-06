// lib/network/network_aware_page.dart
import 'dart:async';
import 'package:cashgo/widgets/Cashier/network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkAwarePage extends StatefulWidget {
  const NetworkAwarePage({Key? key}) : super(key: key);

  @override
  State<NetworkAwarePage> createState() => _NetworkAwarePageState();
}

class _NetworkAwarePageState extends State<NetworkAwarePage> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final NetworkCheck _networkCheck;

  // نعمل Subscription على عنصر واحد بعد تحويل القائمة
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<bool>? _internetStatusSub;

  bool _hasInternet = true;
  bool _initialChecked = false;

  // ننتظر أول frame عشان نتأكد إن ScaffoldMessenger جاهز لعرض SnackBars
  bool _scaffoldReady = false;

  @override
  void initState() {
    super.initState();

    // علامة الجاهزية بعد أول إطار
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

    // لو نفس الحالة وما نريد سناك — نتجاهل
    if (connected == _hasInternet && showSnack) return;

    setState(() => _hasInternet = connected);

    if (!showSnack) return;

    // لو الـ ScaffoldMessenger لسه مش جاهز، نأجل العرض لحد ما يجهز الإطار التالي
    if (!_scaffoldReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack(connected);
      });
    } else {
      _showSnack(connected);
    }
  }

  void _showSnack(bool connected) {
    final messenger = _scaffoldMessengerKey.currentState;
    // إغلاق أي SnackBar سابق
    messenger?.hideCurrentSnackBar();

    if (connected) {
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

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _internetStatusSub?.cancel();
    _networkCheck.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platformLabel = kIsWeb
        ? 'ويب'
        : (Theme.of(context).platform == TargetPlatform.macOS ||
                Theme.of(context).platform == TargetPlatform.windows ||
                Theme.of(context).platform == TargetPlatform.linux)
            ? 'ديسكتوب'
            : 'موبايل';

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('حالة الإنترنت')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasInternet ? Icons.wifi : Icons.wifi_off,
                size: 64,
                color: _hasInternet ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 12),
              Text('المنصة: $platformLabel', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text(_hasInternet ? 'متصل بالإنترنت' : 'غير متصل',
                  style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final connected = await _networkCheck.hasConnection();
                  _handleConnectionChanged(connected);
                },
                child: const Text('إعادة فحص الاتصال الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
