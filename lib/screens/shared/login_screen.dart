// lib/screens/shared/login_screen.dart
import 'dart:io'; // <- موجود لاستخدام Platform و Process و Directory
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/login.dart'; // يحتوي على Session class (currentUsername, currentRole, optional token)
// استبدل المسار إذا كانت ApiService في ملف آخر عندك
import '../../services/Api/Admin/settings.dart';
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

class _LoginScreenState extends State<LoginScreen> {
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

  @override
  void initState() {
    super.initState();
    _printMachineIdentityOnStart();
  }

  @override
  void dispose() {
    _stopPolling();
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
    } catch (e, st) {
      if (kDebugMode) print('Failed to get machine identity: $e\n$st');
      // لو فشلنا في الحصول على hostname سنبقي hostName 'unknown' ونفتح الشاشة (مانعش المستخدمين)
      setState(() {
        hostName = 'unknown';
        _initialChecking = false;
      });
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
        if (kDebugMode)
          print(
              '[LoginScreen] poll result enabled=$enabled for host=$hostName');

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
          if (kDebugMode)
            print('[LoginScreen] maintenance fetch error, will retry.');
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
        return WillPopScope(
          onWillPop: () async => false,
          child: SizedBox(
            width: 300,
            height: 200,
            child: AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'التطبيق متوقف بسبب عدم الاشتراك او عدم التجديد',
                  style: TextStyle(color: AppColorsDark.mainTextDark),
                ),
              ),
              actions: const [],
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
        Session.currentRole = returnedRole;
        Session.canViewCredit = canViewCredit;
        if (token != null && token.isNotEmpty) Session.currentToken = token;

        if (!mounted) return;

        if (status == 'success_offline') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('تم تسجيل الدخول'),
            ),
            duration: Duration(seconds: 2),
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
    // غير ذلك نعرض شاشة تسجيل الدخول العادية
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        title: Text(
          'تسجيل الدخول',
          style: TextStyle(fontSize: 27, color: AppColorsDark.mainTextDark),
        ),
      ),
      body: loading
          ? LoginLoadingShimmer()
          : LayoutBuilder(
              builder: (context, constraints) {
                final logoSize =
                    (constraints.maxHeight * 0.42).clamp(180.0, 360.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 4),
                          Image.asset(
                            "assets/images/logo.png",
                            width: logoSize,
                            height: logoSize,
                            color:
                                AppColorsDark.mainColor.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 18),
                          CustomFormField(
                            controller: usernameController,
                            focusNode: usernameFocus,
                            hint: "اسم المستخدم",
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) {
                              FocusScope.of(context)
                                  .requestFocus(passwordFocus);
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomFormField(
                            controller: passwordController,
                            focusNode: passwordFocus,
                            hint: "رمز الدخول",
                            isPassword: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                          ),
                          const SizedBox(height: 10),
                          if (errorMessage.isNotEmpty)
                            Text(
                              errorMessage,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 23),
                            )
                          else
                            const SizedBox(height: 18),
                          const SizedBox(height: 8),
                          CustomButton(
                            text: "تسجيل دخول",
                            onPressed: _login,
                            isLoading: loading,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
