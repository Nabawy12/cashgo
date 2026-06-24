

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_locked_screen.dart';

class LockedScreen extends StatefulWidget {
  final VoidCallback onActivated;
  const LockedScreen({super.key, required this.onActivated});

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  // 📞 غيّر الرقم ده لرقمك (بصيغة دولية بدون + وبدون مسافات لرابط واتساب)
  static const String supportPhoneDisplay = '+201012126866';
  static const String supportWhatsappNumber = '+201012126866'; // كود مصر + الرقم

  String? _deviceId;
  final _codeController = TextEditingController();
  String? _errorText;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await ActivationService.getOrCreateDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);
  }

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse(
        'https://wa.me/$supportWhatsappNumber?text=${Uri.encodeComponent('السلام عليكم، عايز أفعّل برنامج CashGo. كود الجهاز بتاعي: ${_deviceId ?? ''}')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone() async {
    final uri = Uri.parse('tel:$supportPhoneDisplay');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorText = 'من فضلك ادخل كود التفعيل');
      return;
    }
    setState(() {
      _checking = true;
      _errorText = null;
    });

    final ok = await ActivationService.tryActivate(code);

    if (!mounted) return;
    setState(() => _checking = false);

    if (ok) {
      widget.onActivated();
    } else {
      setState(() => _errorText = 'الكود غير صحيح، تأكد منه مع الدعم الفني');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xff1A1C28),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 56, color: Colors.amber),
                    const SizedBox(height: 16),
                    const Text(
                      'انتهت الفترة التجريبية',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'برنامج CashGo يحتاج تفعيل للاستمرار في الاستخدام.\n'
                          'تواصل مع الدعم الفني لتفعيل البرنامج.',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // كود الجهاز
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xff262935),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'كود الجهاز (قوله للدعم الفني)',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _deviceId ?? '...',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // أزرار التواصل
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openWhatsapp,
                            icon: const Icon(Icons.chat),
                            label: const Text('واتساب'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff25D366),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _callPhone,
                            icon: const Icon(Icons.call),
                            label: const Text('اتصال'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      supportPhoneDisplay,
                      style: const TextStyle(color: Colors.white54),
                    ),

                    const SizedBox(height: 28),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 12),

                    const Text(
                      'إدخال كود التفعيل',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 2),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xff262935),
                        hintText: 'XXXX-XXXX',
                        hintStyle: const TextStyle(color: Colors.white38),
                        errorText: _errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checking ? null : _submitCode,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _checking
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('تفعيل البرنامج'),
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
  }
}
