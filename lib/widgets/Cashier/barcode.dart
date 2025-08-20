import 'package:flutter/material.dart';

class BarcodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onSubmitted;
  final VoidCallback onAddPressed;

  const BarcodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(labelText: 'امسح الباركود أو اكتب واضغط Enter', border: OutlineInputBorder()),
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted,
        ),
      ),
      const SizedBox(width: 12),
      ElevatedButton(onPressed: onAddPressed, child: const Text('أضف')),
    ]);
  }
}
