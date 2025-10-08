// lib/screens/shared/login_screen.dart
import 'dart:convert';
import 'dart:io'; // <- موجود لاستخدام Platform و Process و Directory
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/login.dart'; // يحتوي على Session class (currentUsername, currentRole, optional token)
import '../../services/Api/Admin/settings.dart'; // يحتوي على ApiService.loginOnline
import '../../services/cashier/app_controller.dart';
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
      final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
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

      // بعدما حصلنا على hostname نبدأ polling حتى نتأكد enabled == 0
      _startPollingForMaintenance();
    } catch (e, st) {
      if (kDebugMode) print('Failed to get machine identity: $e\n$st');
      // لو فشلنا في الحصول على hostname سنبقي hostName فارغاً،
      // لكن نبدأ المحاولة مع قيمة 'unknown' عوضاً عن ذلك
      setState(() {
        hostName = 'unknown';
      });
      _startPollingForMaintenance();
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
            final r = await Process.run('networksetup', ['-listallhardwareports']);
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
        if (kDebugMode) print('[LoginScreen] poll result enabled=$enabled for host=$hostName');

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
          if (kDebugMode) print('[LoginScreen] maintenance fetch error, will retry.');
        }
      } catch (e) {
        if (kDebugMode) print('[LoginScreen] polling error: $e');
      }

      // انتظار قبل المحاولة التالية
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Future<int> _fetchEnabledFromServer(String ipMachine) async {
    try {
      final ipToSend = (ipMachine.trim().isEmpty) ? 'unknown' : ipMachine.trim();
      final uri = Uri.https(
        'nabawisolution.com',
        '/app_control.php',
        {
          'action': 'status',
          'ip_machine': ipToSend,
        },
      );

      if (kDebugMode) print('[LoginScreen] Request URI: $uri');

      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (kDebugMode) {
        print('[LoginScreen] Response status: ${res.statusCode}');
        print('[LoginScreen] Response body: ${res.body}');
      }

      if (res.statusCode != 200 || res.body.isEmpty) {
        return -1;
      }

      final Map<String, dynamic> j = jsonDecode(res.body);
      int enabled = 0;
      if (j['enabled'] is int) {
        enabled = j['enabled'] as int;
      } else if (j['enabled'] != null) {
        enabled = int.tryParse(j['enabled'].toString()) ?? -1;
      } else {
        enabled = -1;
      }

      return enabled;
    } catch (e) {
      if (kDebugMode) print('[LoginScreen] _fetchEnabledFromServer error: $e');
      return -1;
    }
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
                child: const Text(
                  'التطبيق متوقف بسبب عدم الاشتراك او عدم التجديد',
                  style: TextStyle(color: Colors.white),
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

  Future<void> _login() async {
    setState(() {
      errorMessage = '';
    });

    // أثناء محاولة تسجيل الدخول نعيد التحقق السريع من الصيانة (لتغطية حالة النقر السريع)
    if (hostName.isNotEmpty) {
      try {
        final enabled = await _fetchEnabledFromServer(hostName);
        if (enabled == 1) {
          // عرض الدايلوج المحلي إن لم يظهر
          if (!_maintenanceDialogShown && mounted) _showLocalMaintenanceDialog();
          return;
        } else if (enabled == -1) {
          // خطأ في التحقق => نمنع المتابعة حسب طلبك (ابقاء الصفحة محجوبة)
          // نعيد محاولة لاحقًا بدل المتابعة
          setState(() {
            errorMessage = 'لا يمكن التحقق من حالة الصيانة حالياً. أعد المحاولة لاحقاً.';
          });
          return;
        }
      } catch (e) {
        if (kDebugMode) print('Maintenance quick-check failed during login: $e');
        setState(() {
          errorMessage = 'حدث خطأ أثناء التحقق من الصيانة.';
        });
        return;
      }
    }

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
      final raw = await ApiService.loginOnline(usernameInput, password);

      if (kDebugMode) {
        print('Login response (raw): $raw');
      }

      // --- تحقق من فشل تسجيل الدخول ---
      if (raw == null || raw['status'] != 'success') {
        setState(() {
          errorMessage = raw?['message']?.toString() ?? 'اسم المستخدم أو كلمة السر غير صحيحة';
        });
        return;
      }

      // --- استخراج الداتا من الرد ---
      Map<String, dynamic> payload = {};
      if (raw.containsKey('data') && raw['data'] is Map) {
        payload = Map<String, dynamic>.from(raw['data'] as Map);
      } else {
        payload = Map<String, dynamic>.from(raw);
      }

      String returnedUsername = payload['username']?.toString() ?? usernameInput;
      String returnedRole = payload['role']?.toString() ?? 'cashier';
      String? token = payload['token']?.toString();

      if (kDebugMode) {
        print('parsed payload: $payload');
        print('returnedUsername: $returnedUsername');
        print('returnedRole: $returnedRole');
        print('token: $token');
      }

      // --- تخزين الـ Session ---
      Session.currentUsername = returnedUsername;
      Session.currentRole = returnedRole;
      if (token != null) Session.currentToken = token;

      if (!mounted) return;

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
          },
        );
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
    // إذا ما خلصنا التحقق من حالة الصيانة نظهر شاشة تحميل كاملة
    if (_initialChecking) {
      return Scaffold(
        backgroundColor: AppColorsDark.bgColor,
        body:  Center(
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child:LoginLoadingShimmer(),
          ),
        ),
      );
    }

    // غير ذلك نعرض شاشة تسجيل الدخول العادية
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        title: const Text(
          'تسجيل الدخول',
          style: TextStyle(fontSize: 27, color: Colors.white),
        ),
      ),
      body: loading
          ? LoginLoadingShimmer()
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.center,
                  child: Image.asset(
                    "assets/images/logo.png",
                    width: 460,
                    height: 460,
                    color: AppColorsDark.mainColor.withOpacity(0.3),
                  ),
                ),
                const SizedBox(height: 8),
                CustomFormField(
                  controller: usernameController,
                  focusNode: usernameFocus,
                  hint: "اسم المستخدم",
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(passwordFocus);
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
                    style: const TextStyle(color: Colors.red, fontSize: 23),
                  )
                else
                  const SizedBox(height: 18),
                const SizedBox(height: 8),
                CustomButton(text: "تسجيل دخول", onPressed: _login),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
