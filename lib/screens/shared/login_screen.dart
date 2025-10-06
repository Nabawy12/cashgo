// lib/screens/shared/login_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    // لو عندك فحص صيانة أو initialization حطّه هنا
    MaintenanceService.checkAndHandle(context);
  }

  Future<void> _login() async {
    setState(() {
      errorMessage = '';
    });

    if (MaintenanceService.isInMaintenance) {
      MaintenanceService.checkAndHandle(context);
      return;
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
                    width: 260,
                    height: 260,
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
                    style: const TextStyle(color: Colors.red,fontSize:23),
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



  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    usernameFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }
}
