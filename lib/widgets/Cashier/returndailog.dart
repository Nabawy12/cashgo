// lib/main.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // RenderRepaintBoundary
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const PrintDemoPage(),
    );
  }
}

class PrintDemoPage extends StatefulWidget {
  const PrintDemoPage({super.key});
  @override
  State<PrintDemoPage> createState() => _PrintDemoPageState();
}

class _PrintDemoPageState extends State<PrintDemoPage> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _isPrinting = false;

  /// Robust capture: waits frames and retries until the boundary is painted
  Future<Uint8List> _captureReceiptAsPng() async {
    const int maxAttempts = 12;
    const Duration attemptDelay = Duration(milliseconds: 120);
    const double pixelRatio = 3.0;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Allow any pending frames to complete
      final Completer<void> frameCompleter = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!frameCompleter.isCompleted) frameCompleter.complete();
      });
      // small delay then wait for post-frame
      await Future.delayed(const Duration(milliseconds: 20));
      await frameCompleter.future;

      final renderObject = _receiptKey.currentContext?.findRenderObject();
      if (renderObject == null) {
        // If not yet created, wait and retry
        if (attempt == maxAttempts - 1) {
          throw Exception('RepaintBoundary غير موجود/لم يُنشأ بعد.');
        }
        await Future.delayed(attemptDelay);
        continue;
      }

      if (renderObject is! RenderRepaintBoundary) {
        throw Exception('العنصر المرتبط بالمفتاح ليس RenderRepaintBoundary.');
      }

      final boundary = renderObject as RenderRepaintBoundary;

      // In debug mode, avoid capturing while boundary still needs paint
      try {
        // debugNeedsPaint exists in debug builds; check only if available
        final bool needsPaint = boundary.debugNeedsPaint;
        if (needsPaint) {
          if (attempt == maxAttempts - 1) {
            throw Exception('العنصر لازال يحتاج للرسم (debugNeedsPaint).');
          }
          await Future.delayed(attemptDelay);
          continue;
        }
      } catch (_) {
        // ignore if debugOnly property isn't available — proceed to try capture
      }

      try {
        final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) throw Exception('فشل تحويل الصورة إلى بايت.');
        return byteData.buffer.asUint8List();
      } catch (e) {
        // Could be the assertion; retry unless last attempt
        if (attempt == maxAttempts - 1) rethrow;
        await Future.delayed(attemptDelay);
      }
    }

    throw Exception('فشل التقاط الصورة بعد عدة محاولات.');
  }

  Future<Uint8List> _buildPdfFromImage(Uint8List pngBytes) async {
    final doc = pw.Document();
    final pageFormat = PdfPageFormat.roll80;
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Center(child: pw.Image(image, fit: pw.BoxFit.fitWidth));
        },
      ),
    );
    return doc.save();
  }

  Future<void> _printReceipt() async {
    setState(() => _isPrinting = true);
    try {
      // أثناء التطوير اجعل العنصر مرئياً (opacity=1.0) حتى تتأكد من الشكل
      // لاحقاً يمكن إبقاؤه غير ظاهر عبر opacity:0.0 في UI
      final png = await _captureReceiptAsPng();
      final pdfBytes = await _buildPdfFromImage(png);
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
    } catch (e) {
      debugPrint('Print error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double receiptWidth = 380; // اضبط عرض الإيصال حسب حاجتك

    final Widget receiptWidget = Container(
      width: receiptWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text('باسم ياسر', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          const SizedBox(height: 6),
          Text('فاتورة مبيعات', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Text('التاريخ: ${DateTime.now()}', style: TextStyle(fontSize: 12)),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الصنف', style: TextStyle(fontSize: 12)),
            Text('الكمية', style: TextStyle(fontSize: 12)),
            Text('السعر', style: TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          ...List.generate(1, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('pepsi', style: TextStyle(fontSize: 12)),
                Text('1', style: TextStyle(fontSize: 12)),
                Text('EGP 15', style: TextStyle(fontSize: 12)),
              ]),
            );
          }),
          const Divider(),
          Align(alignment: Alignment.centerRight, child: Text('الإجمالي: EGP 15', style: TextStyle(fontSize: 14))),
          const SizedBox(height: 10),
          Center(child: Text('شكراً لزيارتكم', style: TextStyle(fontSize: 12))),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('POS Print Demo - بدون فونت مضمّن')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: ElevatedButton.icon(
              icon: _isPrinting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print),
              label: Text(_isPrinting ? 'جاري الطباعة...' : 'طباعة إيصال (بدون فونت مضمّن)'),
              onPressed: _isPrinting ? null : _printReceipt,
            ),
          ),
          const SizedBox(height: 20),
          // لتسهيل التجريب حط Opacity=1.0 مؤقتًا، لو شفت الإيصال مبين تمام خليه 0.0
          Opacity(
            opacity: 1.0, // عيّن 1.0 أثناء التجربة للتأكد من أن العنصر مرسوم، ثم غيِّره إلى 0.0
            child: RepaintBoundary(key: _receiptKey, child: receiptWidget),
          ),
          const SizedBox(height: 10),
          const Text('ملاحظات: النص العربي يعتمد على خطوط النظام في ويندوز'),
        ],
      ),
    );
  }
}