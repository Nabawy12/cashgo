import 'package:cashgo/screens/cashier/cashier_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/login.dart';
import '../../services/cashier/app_controller.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_form.dart';

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
  bool loading = true;


  Future<void> _debugPrintUsers() async {
    final db = await DBHelper.instance.database;
    final rows = await db.query('users', orderBy: 'id');
    print('---- users table ----');
    for (final r in rows) print(r);
    print('---- end users ----');
  }


  @override
  void initState() {
    super.initState();
    MaintenanceService.checkAndHandle(context);
    _loadCurrentUser();
  }


  Future<void> _loadCurrentUser() async {
    try {
      final current = await DBHelper.instance.getCurrentUser();
      if (current != null) {
        final savedUsername = (current['username'] ?? '').toString();
        final savedRole = (current['role'] ?? '').toString();

        // usernameController.text = savedUsername;
        Session.currentUsername = savedUsername;
        Session.currentRole = savedRole;
      }
    } catch (e) {
      // خطأ بسيط في القراءة من DB — تجاهل أو لوج
      // print('Failed to load current user: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void _login() async {
    setState(() {
      errorMessage = '';
    });

    if (MaintenanceService.isInMaintenance) {
      MaintenanceService.checkAndHandle(context); // يعرض الدايالوج لو مش ظاهر
      return;
    }else {

      final username = usernameController.text.trim();
      final password = passwordController.text.trim();

      if (username.isEmpty || password.isEmpty) {
        setState(() {
          errorMessage = 'من فضلك املأ جميع الحقول';
        });
        return;
      }

      try {
        final user = await DBHelper.instance.login(username, password);
        if (user != null) {
          // خزّن المستخدم الحالي في الـ DB (بدل SharedPreferences)
          await DBHelper.instance.setCurrentUserByUsername(user['username'] as String);

          // حدث الSession في الذاكرة
          Session.currentUsername = user['username'];
          Session.currentRole = user['role'];

          // توجيه للشاشة المناسبة
          if (user['role'] == 'admin') {
            Navigator.pushNamed(context, '/admin', arguments: username);
          } else {
            Navigator.pushNamed(context, CashierScreen.routName, arguments: username);
          }
        } else {
          setState(() {
            errorMessage = 'اسم المستخدم أو كلمة المرور غير صحيحه';
          });
        }
      } catch (e) {
        setState(() {
          errorMessage = 'حدث خطأ أثناء تسجيل الدخول';
        });
        // optionally print or log e
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
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Image.asset(
                      "assets/images/logo.png",
                    width: 320,
                    height: 320,
                    color: AppColorsDark.mainColor.withOpacity(0.3),
                  ),
                ),
                SizedBox(height: 12,),
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
                Text(errorMessage, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                CustomButton(text: "تسجيل دخول", onPressed: _login),
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
