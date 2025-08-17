import 'package:flutter/material.dart';
import '../utils/colors.dart';

class CustomFormField extends StatefulWidget {
  final String hint;
  final bool isPassword;
  final bool centerHint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  final bool readOnly;
  final VoidCallback? onTap;

  // ✅ خاصية جديدة للتحكم في الـ autoFocus
  final bool autoFocus;

  const CustomFormField({
    super.key,
    required this.hint,
    this.controller,
    this.isPassword = false,
    this.centerHint = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.autoFocus = false, // ✅ القيمة الافتراضية false
  });

  @override
  State<CustomFormField> createState() => _CustomFormFieldState();
}

class _CustomFormFieldState extends State<CustomFormField> {
  late bool _obscure;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _obscure = widget.isPassword;
    _focusNode = FocusNode();

    // ✅ لو الخاصية autoFocus مفعلة، ندي focus بعد ما الـ widget يبني
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose(); // ✅ لازم نعمل dispose للـ focusNode
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      textAlign: widget.centerHint ? TextAlign.center : TextAlign.start,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      focusNode: _focusNode, // ✅ نمرر الـ focusNode الداخلي
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColorsDark.strokColor,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColorsDark.mainColor,
            width: 2,
          ),
        ),
        suffixIcon: widget.isPassword
            ? IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              _obscure = !_obscure;
            });
          },
        )
            : null,
      ),
      style: const TextStyle(color: Colors.white),
    );
  }
}
