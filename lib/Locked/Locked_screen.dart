// lib/screens/shared/locked_screen.dart
import 'package:cashgo_supermarket/Locked/ActivationService.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LockedScreen extends StatefulWidget {
  final VoidCallback onActivated;
  const LockedScreen({super.key, required this.onActivated});

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen>
    with SingleTickerProviderStateMixin {
  // 📞 غيّر الرقم لرقمك
  static const String _phoneDisplay   = '01XXXXXXXXX';
  static const String _whatsappNumber = '20XXXXXXXXXX';

  late AnimationController _animController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  String? _deviceId;
  final _codeController = TextEditingController();
  final _codeFocus      = FocusNode();
  String? _errorText;
  bool    _checking     = false;
  bool    _codeVisible  = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim  = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _loadDeviceId();
    _animController.forward();
  }

  Future<void> _loadDeviceId() async {
    final id = await ActivationService.getOrCreateDeviceId();
    if (!mounted) return;
    setState(() => _deviceId = id);
  }

  Future<void> _openWhatsapp() async {
    final msg = Uri.encodeComponent(
        'السلام عليكم، عايز أفعّل برنامج CashGo. كود الجهاز: ${_deviceId ?? ''}');
    final uri = Uri.parse('https://wa.me/$_whatsappNumber?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone() async {
    final uri = Uri.parse('tel:$_phoneDisplay');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _copyDeviceId() {
    if (_deviceId == null) return;
    Clipboard.setData(ClipboardData(text: _deviceId!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم نسخ كود الجهاز'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xff262935),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorText = 'أدخل كود التفعيل أولاً');
      return;
    }
    setState(() { _checking = true; _errorText = null; });
    final ok = await ActivationService.tryActivate(code);
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      widget.onActivated();
    } else {
      setState(() => _errorText = 'الكود غير صحيح، تواصل مع الدعم');
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xff0F1120),
        body: Stack(
          children: [
            // خلفية gradient دائرية
            Positioned(
              top: -120, right: -80,
              child: _GlowCircle(color: const Color(0xff6C63FF), size: 350),
            ),
            Positioned(
              bottom: -100, left: -60,
              child: _GlowCircle(color: const Color(0xff00BFA5), size: 280),
            ),

            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          children: [
                            // أيقونة القفل
                            Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xff6C63FF), Color(0xff00BFA5)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xff6C63FF).withOpacity(0.4),
                                    blurRadius: 24, spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.lock_rounded,
                                  color: Colors.white, size: 36),
                            ),
                            const SizedBox(height: 24),

                            const Text(
                              'انتهت الفترة التجريبية',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'للاستمرار في استخدام CashGo، تواصل مع الدعم الفني للحصول على كود التفعيل.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14, height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),

                            // بطاقة كود الجهاز
                            _GlassCard(
                              child: Column(
                                children: [
                                  Text(
                                    'كود الجهاز',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _deviceId ?? '...',
                                        style: const TextStyle(
                                          color: Color(0xff6C63FF),
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: _copyDeviceId,
                                        child: Icon(
                                          Icons.copy_rounded,
                                          color: Colors.white.withOpacity(0.4),
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'أعطِ هذا الكود للدعم الفني',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // أزرار التواصل
                            Row(
                              children: [
                                Expanded(
                                  child: _ContactButton(
                                    icon: Icons.chat_rounded,
                                    label: 'واتساب',
                                    color: const Color(0xff25D366),
                                    onTap: _openWhatsapp,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ContactButton(
                                    icon: Icons.call_rounded,
                                    label: 'اتصال',
                                    color: const Color(0xff5C6BC0),
                                    onTap: _callPhone,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // قسم إدخال الكود
                            _GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'كود التفعيل',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => setState(
                                                () => _codeVisible = !_codeVisible),
                                        child: Icon(
                                          _codeVisible
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _codeController,
                                    focusNode: _codeFocus,
                                    obscureText: !_codeVisible,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'XXXX-XXXX',
                                      hintStyle: TextStyle(
                                        color: Colors.white.withOpacity(0.2),
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      filled: true,
                                      fillColor:
                                      Colors.white.withOpacity(0.05),
                                      errorText: _errorText,
                                      errorStyle: const TextStyle(
                                          color: Color(0xffFF5252)),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color:
                                            Colors.white.withOpacity(0.1)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color:
                                            Colors.white.withOpacity(0.1)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xff6C63FF),
                                            width: 1.5),
                                      ),
                                    ),
                                    onSubmitted: (_) => _submitCode(),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xff6C63FF),
                                            Color(0xff00BFA5)
                                          ],
                                        ),
                                        borderRadius:
                                        BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xff6C63FF)
                                                .withOpacity(0.3),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                        _checking ? null : _submitCode,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: _checking
                                            ? const SizedBox(
                                          width: 20, height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                            : const Text(
                                          'تفعيل البرنامج',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _phoneDisplay,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets مساعدة ──────────────────────────────────────────────────

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.25), Colors.transparent],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}