// lib/screens/shared/login_screen.dart
import 'dart:io'; // <- موجود لاستخدام Platform و Process و Directory
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/login.dart'; // يحتوي على Session class (currentUsername, currentRole, optional token)
// استبدل المسار إذا كانت ApiService في ملف آخر عندك
import '../../services/Api/Admin/settings.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Loading/Shared/login.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_form.dart';
import '../../screens/cashier/cashier_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final usernameFocus = FocusNode();
  final passwordFocus = FocusNode();

  String errorMessage = '';
  bool loading = false;
  String hostName = '';

  // إذا true => الصفحة محجوبة (loading) لحد ما نتأكد ان enabled == 0
  bool _initialChecking = true;

  // لإدارة حلقة الـ polling
  bool _pollingActive = false;

  // لو دايالوغ الصيانة ظاهر
  bool _maintenanceDialogShown = false;

  // --- عناصر جديدة لتحسين الـ UX/UI ---
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _printMachineIdentityOnStart();
  }

  @override
  void dispose() {
    _stopPolling();
    _entranceController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    usernameFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  /// يجمع ويطبع اسم الجهاز (hostname)، نظام التشغيل، وعناوين MAC الممكنة.
  Future<void> _printMachineIdentityOnStart() async {
    try {
      final hostname = Platform.localHostname;
      final os =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      final macs = await _getMacAddresses();

      final sb = StringBuffer();
      sb.writeln('--- Machine Identity ---');
      sb.writeln('Hostname: $hostname');
      sb.writeln('OS: $os');
      if (macs.isEmpty) {
        sb.writeln('MAC addresses: (none found)');
      } else {
        sb.writeln('MAC addresses: ${macs.join(', ')}');
      }

      setState(() {
        hostName = hostname;
      });

      if (kDebugMode) {
        print(sb.toString());
      }

      setState(() {
        _initialChecking = false;
      });
      _entranceController.forward();
    } catch (e, st) {
      if (kDebugMode) print('Failed to get machine identity: $e\n$st');
      // لو فشلنا في الحصول على hostname سنبقي hostName 'unknown' ونفتح الشاشة (مانعش المستخدمين)
      setState(() {
        hostName = 'unknown';
        _initialChecking = false;
      });
      _entranceController.forward();
    }
  }

  Future<List<String>> _getMacAddresses() async {
    final macSet = <String>{};
    final macRegex = RegExp(r'([0-9A-Fa-f]{2}([:-])){5}[0-9A-Fa-f]{2}');

    try {
      if (Platform.isWindows) {
        try {
          final r = await Process.run('getmac', []);
          final out = r.stdout.toString() + '\n' + r.stderr.toString();
          for (final m in macRegex.allMatches(out)) {
            macSet.add(m.group(0)!.replaceAll('-', ':').toLowerCase());
          }
        } catch (_) {}

        if (macSet.isEmpty) {
          try {
            final r = await Process.run('ipconfig', ['/all']);
            final out = r.stdout.toString() + '\n' + r.stderr.toString();
            for (final m in macRegex.allMatches(out)) {
              macSet.add(m.group(0)!.replaceAll('-', ':').toLowerCase());
            }
          } catch (_) {}
        }
      } else if (Platform.isMacOS) {
        try {
          final r = await Process.run('ifconfig', []);
          final out = r.stdout.toString() + '\n' + r.stderr.toString();
          final etherRegex = RegExp(r'ether\s+([0-9a-fA-F:]{17})');
          for (final m in etherRegex.allMatches(out)) {
            macSet.add(m.group(1)!.toLowerCase());
          }
          for (final m in macRegex.allMatches(out)) {
            macSet.add(m.group(0)!.toLowerCase());
          }
        } catch (_) {}

        if (macSet.isEmpty) {
          try {
            final r =
            await Process.run('networksetup', ['-listallhardwareports']);
            final out = r.stdout.toString();
            final rx = RegExp(r'Ethernet Address:\s*([0-9a-fA-F:]{17})');
            for (final m in rx.allMatches(out)) {
              macSet.add(m.group(1)!.toLowerCase());
            }
          } catch (_) {}
        }
      } else if (Platform.isLinux) {
        try {
          final r = await Process.run('ip', ['link']);
          final out = r.stdout.toString() + '\n' + r.stderr.toString();
          final linkRegex = RegExp(r'link/ether\s+([0-9a-fA-F:]{17})');
          for (final m in linkRegex.allMatches(out)) {
            macSet.add(m.group(1)!.toLowerCase());
          }
          for (final m in macRegex.allMatches(out)) {
            macSet.add(m.group(0)!.toLowerCase());
          }
        } catch (_) {}

        try {
          final dir = Directory('/sys/class/net');
          if (await dir.exists()) {
            await for (final ent in dir.list()) {
              final addrFile = File('${ent.path}/address');
              if (await addrFile.exists()) {
                final addr = (await addrFile.readAsString()).trim();
                if (macRegex.hasMatch(addr)) macSet.add(addr.toLowerCase());
              }
            }
          }
        } catch (_) {}
      } else {
        try {
          final r1 = await Process.run('ifconfig', []);
          for (final m in macRegex.allMatches(r1.stdout.toString())) {
            macSet.add(m.group(0)!.toLowerCase());
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error while extracting MACs: $e');
    }

    return macSet.toList();
  }

  void _startPollingForMaintenance() {
    if (_pollingActive) return;
    _pollingActive = true;
    _pollLoop();
  }

  void _stopPolling() {
    _pollingActive = false;
  }

  Future<void> _pollLoop() async {
    // تستمر الحلقة طالما _pollingActive true و الشاشة mounted
    while (_pollingActive && mounted) {
      try {
        final enabled = await _fetchEnabledFromServer(hostName);
        if (kDebugMode) {
          print(
              '[LoginScreen] poll result enabled=$enabled for host=$hostName');
        }

        if (enabled == 1) {
          // عرض دايالوغ الصيانة إذا لم يكن ظاهرًا
          if (!_maintenanceDialogShown && mounted) {
            _showLocalMaintenanceDialog();
          }
          // ننتظر ثم نكرر الفحص (حتى تتحول القيمة إلى 0)
        } else if (enabled == 0) {
          // لو كان الدايلوج ظاهر، اغلقه
          if (_maintenanceDialogShown && mounted) {
            try {
              Navigator.of(context, rootNavigator: true).pop(); // يغلق الدايلوج
            } catch (_) {}
            _maintenanceDialogShown = false;
          }
          // اوقف polling واسمح للشاشة بالظهور
          if (mounted) {
            setState(() {
              _initialChecking = false;
            });
          }
          _pollingActive = false;
          return;
        } else {
          // enabled == -1 => خطأ في الطلب. نواصل المحاولة ولكن لا نغلق الصفحة.
          if (kDebugMode) {
            print('[LoginScreen] maintenance fetch error, will retry.');
          }
        }
      } catch (e) {
        if (kDebugMode) print('[LoginScreen] polling error: $e');
      }

      // انتظار قبل المحاولة التالية
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Future<int> _fetchEnabledFromServer(String ipMachine) async {
    return 0;
  }

  void _showLocalMaintenanceDialog() {
    if (!mounted) return;
    _maintenanceDialogShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: AppColorsDark.bgCardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.build_rounded,
                        color: Colors.orange,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'التطبيق متوقف مؤقتًا',
                      style: TextStyle(
                        color: AppColorsDark.mainTextDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'بسبب عدم الاشتراك أو عدم التجديد، برجاء التواصل مع الدعم الفني',
                      style: TextStyle(
                        color: AppColorsDark.mainTextDark.withOpacity(0.7),
                        fontSize: 14,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      // عندما يُغلَق الدايلوج (برمجيًا) نحدّث الحالة
      _maintenanceDialogShown = false;
    });
  }

  // --- helper: استخراج payload المستخدم بشكل مرن من أشكال الاستجابة المختلفة ---
  Map<String, dynamic> _extractUserPayload(dynamic raw) {
    try {
      if (raw == null) return {};

      // case A: raw has 'data' and it's a Map
      if (raw is Map && raw['data'] is Map) {
        final Map<String, dynamic> topData =
        Map<String, dynamic>.from(raw['data']);

        // server sometimes returns { data: { data: { user... } } }
        if (topData['data'] is Map) {
          return Map<String, dynamic>.from(topData['data'] as Map);
        }

        // queued / local case: { status: 'success_offline', data: local } where local may contain 'raw'
        if (topData.containsKey('username')) {
          return topData;
        }
        if (topData.containsKey('raw') && topData['raw'] is Map) {
          return Map<String, dynamic>.from(topData['raw'] as Map);
        }

        // fallback: return topData as-is
        return topData;
      }

      // case B: raw itself is a Map describing the user
      if (raw is Map && raw.containsKey('username')) {
        return Map<String, dynamic>.from(raw);
      }

      // default: cannot extract
      return {};
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to extract user payload: $e');
      return {};
    }
  }

  Future<void> _login() async {
    setState(() {
      errorMessage = '';
    });

    final usernameInput = usernameController.text.trim();
    final password = passwordController.text.trim();

    if (usernameInput.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'من فضلك املأ جميع الحقول';
      });
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      // Offline-only login against local SQLite.
      final raw =
      await ApiService.login(usernameInput, password, allowOffline: true);

      if (kDebugMode) {
        print('Login response (raw): $raw');
      }

      if (raw == null) {
        setState(() {
          errorMessage = 'اسم المستخدم أو كلمة السر غير صحيحة';
        });
        return;
      }

      final status = (raw['status'] ?? '').toString();

      if (status == 'success' || status == 'success_offline') {
        // استخدم الدالة المرنة لاستخراج payload
        final extracted = _extractUserPayload(raw);

        Map<String, dynamic> finalPayload = {};
        if (extracted.isNotEmpty) {
          finalPayload = extracted;
        } else if (raw is Map && raw['data'] is Map) {
          finalPayload = Map<String, dynamic>.from(raw['data']);
        } else if (raw is Map) {
          finalPayload = Map<String, dynamic>.from(raw);
        }

        String returnedUsername =
            finalPayload['username']?.toString() ?? usernameInput;
        String returnedRole = finalPayload['role']?.toString() ?? 'cashier';
        String? token =
            finalPayload['token']?.toString() ?? raw['token']?.toString();
        final rawPermissions = finalPayload['permissions'];
        final canViewCredit = finalPayload['can_view_credit'] == 1 ||
            finalPayload['can_view_credit'] == true ||
            finalPayload['can_view_credit']?.toString() == '1' ||
            (rawPermissions is Map &&
                (rawPermissions['can_view_credit'] == true ||
                    rawPermissions['can_view_credit'] == 1 ||
                    rawPermissions['can_view_credit']?.toString() == '1'));

        // --- تخزين الـ Session ---
        Session.currentUsername = returnedUsername;
        Session.updateDateTime(); // record exact login time as shift start
        final shiftKey =
            'current_shift_start_${returnedUsername.trim().toLowerCase()}';
        final db = await DBHelper.instance.database;
        final unclosed = await db.rawQuery(
          '''
          SELECT COUNT(*) as cnt
          FROM sales
          WHERE TRIM(COALESCE(cashier_username,'')) = ?
            AND COALESCE(drawer_withdrawn,0) = 0
          ''',
          [returnedUsername.trim()],
        );
        final hasUnclosedSales =
            ((unclosed.first['cnt'] as num?)?.toInt() ?? 0) > 0;

        if (!hasUnclosedSales) {
          await DBHelper.instance.setAppSetting(
            shiftKey,
            DateTime.now().toIso8601String(),
          );
          debugPrint('[Login] new shift start saved for $returnedUsername');
        } else {
          final existingShiftStart = await DBHelper.instance.getAppSetting(
            shiftKey,
          );
          debugPrint(
              '[Login] keeping existing shift start for $returnedUsername (has unclosed sales) existing=$existingShiftStart');
        }
        Session.currentRole = returnedRole;
        Session.canViewCredit = canViewCredit;
        if (token != null && token.isNotEmpty) Session.currentToken = token;

        if (!mounted) return;

        if (status == 'success_offline') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColorsDark.bgCardColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 10),
                  Text(
                    'تم تسجيل الدخول',
                    style: TextStyle(color: AppColorsDark.mainTextDark),
                  ),
                ],
              ),
            ),
            duration: const Duration(seconds: 2),
          ));
        }

        // --- التنقل للشاشات حسب الدور ---
        if (returnedRole == 'admin') {
          Navigator.pushNamed(context, '/admin', arguments: returnedUsername);
        } else {
          Navigator.pushReplacementNamed(
            context,
            CashierScreen.routName,
            arguments: {
              'username': returnedUsername,
              'role': returnedRole,
              'token': Session.currentToken,
              'can_view_credit': canViewCredit,
            },
          );
        }
      } else {
        // حالة فشل
        setState(() {
          errorMessage = raw['message']?.toString() ??
              'اسم المستخدم أو كلمة السر غير صحيحة';
        });
        return;
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('Login error: $e\n$st');
      }
      setState(() {
        errorMessage = 'حدث خطأ أثناء تسجيل الدخول';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColorsDark.bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColorsDark.mainColor.withOpacity(0.10),
              AppColorsDark.bgColor,
              AppColorsDark.bgColor,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // زخرفة خلفية دائرية خفيفة لإضافة عمق للتصميم
            Positioned(
              top: -80,
              right: -60,
              child: _decorativeCircle(220, AppColorsDark.mainColor
                  .withOpacity(0.12)),
            ),
            Positioned(
              bottom: -100,
              left: -80,
              child: _decorativeCircle(260, AppColorsDark.mainColor
                  .withOpacity(0.08)),
            ),

            SafeArea(
              child: _initialChecking
                  ? const LoginLoadingShimmer()
                  : LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 520;
                  final logoSize =
                  (constraints.maxHeight * 0.20).clamp(90.0, 150.0);

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 420 : double.infinity,
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // --- الشعار ---
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColorsDark.bgCardColor,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColorsDark.mainColor
                                              .withOpacity(0.25),
                                          blurRadius: 30,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        "assets/images/logo.png",
                                        width: logoSize,
                                        height: logoSize,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // --- عنوان ترحيبي ---
                                  Text(
                                    'مرحبًا بعودتك',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColorsDark.mainTextDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'سجّل دخولك للمتابعة إلى حسابك',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColorsDark.mainTextDark
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 28),

                                  // --- بطاقة الفورم ---
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color:
                                      AppColorsDark.bgCardColor,
                                      borderRadius:
                                      BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(0.18),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        CustomFormField(
                                          controller:
                                          usernameController,
                                          focusNode: usernameFocus,
                                          hint: "اسم المستخدم",
                                          keyboardType:
                                          TextInputType.name,
                                          textInputAction:
                                          TextInputAction.next,
                                          onFieldSubmitted: (_) {
                                            FocusScope.of(context)
                                                .requestFocus(
                                                passwordFocus);
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        CustomFormField(
                                          controller:
                                          passwordController,
                                          focusNode: passwordFocus,
                                          hint: "رمز الدخول",
                                          isPassword: true,
                                          textInputAction:
                                          TextInputAction.done,
                                          onFieldSubmitted: (_) =>
                                              _login(),
                                        ),

                                        // --- رسالة الخطأ (متحركة) ---
                                        AnimatedSize(
                                          duration: const Duration(
                                              milliseconds: 250),
                                          curve: Curves.easeOut,
                                          child: errorMessage.isEmpty
                                              ? const SizedBox(
                                              height: 0)
                                              : Padding(
                                            padding:
                                            const EdgeInsets
                                                .only(
                                                top: 14),
                                            child: Container(
                                              width:
                                              double.infinity,
                                              padding:
                                              const EdgeInsets
                                                  .symmetric(
                                                  horizontal:
                                                  12,
                                                  vertical:
                                                  10),
                                              decoration:
                                              BoxDecoration(
                                                color: Colors.red
                                                    .withOpacity(
                                                    0.10),
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                    12),
                                                border: Border.all(
                                                    color: Colors
                                                        .red
                                                        .withOpacity(
                                                        0.35)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .error_outline_rounded,
                                                    color: Colors
                                                        .redAccent,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(
                                                      width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      errorMessage,
                                                      style:
                                                      const TextStyle(
                                                        color: Colors
                                                            .redAccent,
                                                        fontSize:
                                                        13.5,
                                                        fontWeight:
                                                        FontWeight
                                                            .w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 22),

                                        SizedBox(
                                          width: double.infinity,
                                          child: CustomButton(
                                            text: "تسجيل دخول",
                                            onPressed: _login,
                                            isLoading: loading,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // --- تذييل بسيط لاسم الجهاز (اختياري، للدعم الفني) ---
                                  if (hostName.isNotEmpty)
                                    Text(
                                      hostName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColorsDark
                                            .mainTextDark
                                            .withOpacity(0.35),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorativeCircle(double size, Color color) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}