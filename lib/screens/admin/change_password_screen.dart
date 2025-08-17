import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String username;
  const ChangePasswordScreen({super.key, required this.username});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final newPasswordController = TextEditingController();
  String message = '';

  void _changePassword() async {
    final newPassword = newPasswordController.text.trim();
    if (newPassword.isEmpty) {
      setState(() => message = 'أدخل كلمة مرور جديدة');
      return;
    }

    await DBHelper.instance.changePassword(widget.username, newPassword);
    setState(() => message = 'تم تغيير كلمة المرور بنجاح');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Colors.white70
        ),
        backgroundColor: Colors.transparent,
          elevation: 0.0,
          title: Text(
          'تغيير كلمة المرور',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20
        ),
      )
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomFormField(
                    hint: 'كلمة مرور جديدة',
                    controller: newPasswordController,
                  isPassword: true,
                ),
                const SizedBox(height: 20),
                CustomButton(
                    text: 'تغيير',
                    onPressed: _changePassword
                ),
                const SizedBox(height: 10),
                Text(message, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
