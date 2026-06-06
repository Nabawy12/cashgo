// lib/network/network_check_io.dart
import 'dart:async';
import 'dart:io';

/// NetworkCheck for IO platforms (mobile + desktop).
///
/// Uses a lightweight TCP connect (Socket.connect) to a public IP (default: 8.8.8.8:53)
/// to determine if there's real Internet connectivity.
/// You can change host/port to your own reliable endpoint.
class NetworkCheck {
  final InternetAddress host;
  final int port;
  final Duration timeout;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  NetworkCheck({
    InternetAddress? host,
    this.port = 53,
    this.timeout = const Duration(seconds: 4),
  }) : host = host ?? InternetAddress('8.8.8.8');

  /// بث لحالة الاتصال الحقيقية (true = connected)
  Stream<bool> get onStatusChange => _controller.stream;

  /// فحص فوري
  Future<bool> hasConnection() async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يمكنك استدعاء هذا عندما تريد أن تُعيد إرسال الحالة الحالية (مثلاً بعد تغيير الواجهة)
  Future<void> emitCurrent() async {
    final connected = await hasConnection();
    if (!_controller.isClosed) _controller.add(connected);
  }

  void dispose() {
    _controller.close();
  }
}
