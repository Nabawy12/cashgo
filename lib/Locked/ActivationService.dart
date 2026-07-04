// lib/services/activation_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import '../services/db/db_helper.dart';

class ActivationService {
  // ⚠️ مختلف عن نسخة VAPE عشان كل مشروع يكون مستقل
  static const String _secretSalt = 'CashGo-Super-Secret-2026-M3kR';

  static const int trialDays = 7;

  static const String _kDeviceId   = 'device_id';
  static const String _kFirstRun   = 'first_run_date';
  static const String _kActivated  = 'is_activated';
  static const String _kActivationCode = 'activation_code_used';

  static Future<String> getOrCreateDeviceId() async {
    final existing = await DBHelper.instance.getAppSetting(_kDeviceId);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    final newId = _generateDeviceId();
    await DBHelper.instance.setAppSetting(_kDeviceId, newId);
    return newId;
  }

  static String _generateDeviceId() {
    final rnd = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String block(int len) =>
        List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'CG-${block(4)}-${block(4)}';
  }

  static Future<DateTime> ensureFirstRunDate() async {
    final existing = await DBHelper.instance.getAppSetting(_kFirstRun);
    if (existing != null && existing.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(existing);
      if (parsed != null) return parsed;
    }
    final now = DateTime.now();
    await DBHelper.instance.setAppSetting(_kFirstRun, now.toIso8601String());
    return now;
  }

  static Future<bool> isActivated() async {
    final v = await DBHelper.instance.getAppSetting(_kActivated);
    return v == '1';
  }

  static Future<int> remainingTrialDays() async {
    final firstRun = await ensureFirstRunDate();
    final elapsed  = DateTime.now().difference(firstRun).inDays;
    final remaining = trialDays - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  static const String _kLastSeen = 'last_seen_date';

  static Future<bool> isLocked() async {
    if (await isActivated()) return false;

    final db = DBHelper.instance;
    final now = DateTime.now();

    // اقرأ آخر تاريخ شوفناه
    final lastSeenStr = await db.getAppSetting(_kLastSeen);
    final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;

    // لو التاريخ الحالي أصغر من آخر تاريخ سجلناه → تلاعب بالتاريخ → قفل فوري
    if (lastSeen != null && now.isBefore(lastSeen)) {
      return true;
    }

    // حدّث آخر تاريخ مشوف
    await db.setAppSetting(_kLastSeen, now.toIso8601String());

    return (await remainingTrialDays()) <= 0;
  }

  static String _expectedCodeFor(String deviceId) {
    final raw  = '$deviceId::$_secretSalt';
    final hash = sha256.convert(utf8.encode(raw)).toString().toUpperCase();
    return '${hash.substring(0, 4)}-${hash.substring(4, 8)}';
  }

  static Future<bool> tryActivate(String enteredCode) async {
    final deviceId = await getOrCreateDeviceId();
    final expected = _expectedCodeFor(deviceId);
    final normalized = enteredCode.trim().toUpperCase().replaceAll(' ', '');
    if (normalized == expected.replaceAll(' ', '')) {
      await DBHelper.instance.setAppSetting(_kActivated, '1');
      await DBHelper.instance.setAppSetting(_kActivationCode, normalized);
      return true;
    }
    return false;
  }
}