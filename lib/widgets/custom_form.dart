import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/colors.dart';

class CustomFormField extends StatefulWidget {
  final String hint;
  final bool isPassword;
  final bool centerHint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final bool label;

  final bool readOnly;
  final VoidCallback? onTap;

  final bool autoFocus;

  final FocusNode? focusNode;

  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

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
    this.autoFocus = false,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.label = false,
  });

  @override
  State<CustomFormField> createState() => _CustomFormFieldState();
}

class _CustomFormFieldState extends State<CustomFormField> {
  late bool _obscure;
  FocusNode? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _obscure = widget.isPassword;

    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          (widget.focusNode ?? _internalFocusNode)?.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.label == true) ...[
          Text(
            widget.hint,
            style: TextStyle(color: AppColorsDark.mainColor),
          ),
          SizedBox(height: 10),
        ],
        TextFormField(
          inputFormatters: [
            ...(widget.inputFormatters ?? []),
            // ✅ فورماتر يحول أي أرقام عربية إلى إنجليزية
            TextInputFormatter.withFunction((oldValue, newValue) {
              const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
              const english = [
                '0',
                '1',
                '2',
                '3',
                '4',
                '5',
                '6',
                '7',
                '8',
                '9'
              ];

              String text = newValue.text;
              for (int i = 0; i < arabic.length; i++) {
                text = text.replaceAll(arabic[i], english[i]);
              }

              return newValue.copyWith(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
            }),
          ],
          controller: widget.controller,
          obscureText: _obscure,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          onChanged: widget.onChanged,
          textAlign: widget.centerHint ? TextAlign.center : TextAlign.start,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          focusNode: widget.focusNode ?? _internalFocusNode,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: AppColorsDark.mainTextLight),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColorsDark.strokColor,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColorsDark.mainColor,
                width: 2,
              ),
            ),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: AppColorsDark.mainTextDark,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscure = !_obscure;
                      });
                    },
                  )
                : null,
          ),
          style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 18),
        ),
      ],
    );
  }
}
