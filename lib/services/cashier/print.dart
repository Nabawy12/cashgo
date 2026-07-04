// print_service.dart
// PrintService: capture RepaintBoundary -> PNG -> Flutter preview dialog.
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cashgo_supermarket/utils/colors.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/cart.dart';
import '../db/db_helper.dart';

class PrintService {
  static bool _cairoLoadedToEngine = false;

  static Future<void> ensureCairoLoaded() async {
    if (_cairoLoadedToEngine) return;
    try {
      final loader = FontLoader('Cairo');
      loader.addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
      await loader.load();
      _cairoLoadedToEngine = true;
      debugPrint('Cairo font loaded into Flutter engine');
    } catch (e) {
      debugPrint('Failed to load Cairo font into engine: $e');
    }
  }

  static Future<void> printThermalReceipt({
    required Map<int, CartItem> cart,
    required double paid,
    required String cashierUsername,
    String? discountType,
    double discountValue = 0.0,
  }) async {
    final settings = await DBHelper.instance.getShopSettings();
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final subtotal =
        cart.values.fold<double>(0, (sum, item) => sum + item.subtotal);
    double discount = 0.0;
    if ((discountType ?? '').toLowerCase() == 'percent') {
      discount = subtotal * (discountValue.clamp(0, 100) / 100);
    } else if ((discountType ?? '').toLowerCase() == 'fixed') {
      discount = discountValue.clamp(0, subtotal);
    }
    final total = (subtotal - discount).clamp(0.0, double.infinity);
    final change = (paid - total).clamp(0.0, double.infinity);
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
            80 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm,
            marginAll: 4 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(settings['shop_name'] ?? 'CashGo',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            if ((settings['shop_address'] ?? '').isNotEmpty)
              pw.Center(child: pw.Text(settings['shop_address']!)),
            if ((settings['shop_phone'] ?? '').isNotEmpty)
              pw.Center(child: pw.Text(settings['shop_phone']!)),
            pw.Divider(),
            pw.Text('التاريخ: $now'),
            pw.Text('الكاشير: $cashierUsername'),
            pw.Divider(),
            pw.Row(children: [
              pw.Expanded(flex: 4, child: pw.Text('الصنف')),
              pw.Expanded(child: pw.Text('كم')),
              pw.Expanded(child: pw.Text('سعر')),
              pw.Expanded(child: pw.Text('الإجمالي')),
            ]),
            pw.Divider(),
            ...cart.values.map((item) {
              return pw.Row(children: [
                pw.Expanded(flex: 4, child: pw.Text(item.product.name)),
                pw.Expanded(child: pw.Text('${item.quantity}')),
                pw.Expanded(
                    child:
                        pw.Text(item.product.sellingPrice.toStringAsFixed(2))),
                pw.Expanded(child: pw.Text(item.subtotal.toStringAsFixed(2))),
              ]);
            }),
            pw.Divider(),
            pw.Text('الإجمالي: ${subtotal.toStringAsFixed(2)}'),
            if (discount > 0) pw.Text('الخصم: ${discount.toStringAsFixed(2)}'),
            pw.Text('الصافي: ${total.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('المدفوع: ${paid.toStringAsFixed(2)}'),
            pw.Text('الباقي: ${change.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );

    debugPrint('[PrintService] opening thermal receipt print job');
    await Future.any<void>([
      Printing.layoutPdf(
        name: 'cashgo_receipt',
        format: const PdfPageFormat(
            80 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm,
            marginAll: 4 * PdfPageFormat.mm),
        onLayout: (_) => doc.save(),
      ),
      Future<void>.delayed(const Duration(seconds: 3), () {
        throw TimeoutException('Printing.layoutPdf timed out');
      }),
    ]);
    debugPrint('[PrintService] thermal receipt print job completed');
  }

  /// Capture a RepaintBoundary referenced by [key] into PNG bytes.
  /// This keeps the previous behavior for cases where the widget is already painted.
  static Future<Uint8List> captureKeyAsPng(GlobalKey key,
      {double pixelRatio = 3.0}) async {
    const int maxAttempts = 20;
    const Duration attemptDelay = Duration(milliseconds: 150);
    const Duration extraDelayAfterFrame = Duration(milliseconds: 40);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      await Future.delayed(extraDelayAfterFrame);

      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null) {
        debugPrint('captureKeyAsPng: renderObject == null (attempt $attempt)');
        if (attempt == maxAttempts - 1)
          throw Exception('RepaintBoundary غير موجود/لم يُنشأ بعد.');
        await Future.delayed(attemptDelay);
        continue;
      }

      if (renderObject is! RenderRepaintBoundary) {
        throw Exception('العنصر المرتبط بالمفتاح ليس RenderRepaintBoundary.');
      }

      bool stillNeedsPaint = false;
      assert(() {
        stillNeedsPaint = (renderObject as RenderObject).debugNeedsPaint;
        return true;
      }());

      if (stillNeedsPaint) {
        debugPrint(
            'captureKeyAsPng: boundary stillNeedsPaint == true (attempt $attempt). Waiting...');
        if (attempt == maxAttempts - 1) {
          throw Exception('الودجت لم تُرسم بعد (needsPaint) بعد عدة محاولات.');
        }
        await Future.delayed(attemptDelay);
        continue;
      }

      final boundary = renderObject as RenderRepaintBoundary;
      try {
        final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        try {
          img.dispose();
        } catch (_) {}
        if (byteData == null) throw Exception('فشل تحويل الصورة إلى بايت.');
        return byteData.buffer.asUint8List();
      } on AssertionError catch (e, st) {
        debugPrint('toImage assertion (attempt $attempt): $e\n$st');
        if (attempt == maxAttempts - 1) rethrow;
        await Future.delayed(attemptDelay);
        continue;
      } catch (e, st) {
        debugPrint(
            'captureKeyAsPng unexpected error (attempt $attempt): $e\n$st');
        if (attempt == maxAttempts - 1) rethrow;
        await Future.delayed(attemptDelay);
        continue;
      }
    }

    throw Exception('فشل التقاط الصورة بعد عدة محاولات.');
  }

  /// Capture a widget by inserting it into the Overlay (guarantees it will be painted)
  static Future<Uint8List> captureWidgetViaOverlay(
    BuildContext context,
    Widget widget, {
    double width = 220,
    double pixelRatio = 2.0,
    int maxAttempts = 20,
  }) async {
    final repaintKey = GlobalKey();
    final overlayState = Overlay.of(context);
    if (overlayState == null) {
      throw Exception('No Overlay found in this context.');
    }

    final entry = OverlayEntry(builder: (ctx) {
      // Transparent Material to allow painting without blocking user visually.
      return Material(
        color: Colors.transparent,
        child: Center(
          child: SizedBox(
            width: width,
            child: RepaintBoundary(
              key: repaintKey,
              child: widget,
            ),
          ),
        ),
      );
    });

    overlayState.insert(entry);

    try {
      const attemptDelay = Duration(milliseconds: 120);
      const extraAfterFrame = Duration(milliseconds: 40);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        await SchedulerBinding.instance.endOfFrame;
        await Future.delayed(extraAfterFrame);

        final renderObject = repaintKey.currentContext?.findRenderObject();
        if (renderObject == null) {
          debugPrint(
              'captureWidgetViaOverlay: renderObject == null (attempt $attempt)');
          await Future.delayed(attemptDelay);
          continue;
        }

        if (renderObject is! RenderRepaintBoundary) {
          throw Exception(
              'Widget wrapped by key is not a RenderRepaintBoundary.');
        }

        bool stillNeedsPaint = false;
        assert(() {
          stillNeedsPaint = (renderObject as RenderObject).debugNeedsPaint;
          return true;
        }());

        if (stillNeedsPaint) {
          debugPrint(
              'captureWidgetViaOverlay: boundary stillNeedsPaint == true (attempt $attempt). Waiting...');
          await Future.delayed(attemptDelay);
          continue;
        }

        final boundary = renderObject as RenderRepaintBoundary;

        if (boundary.size.width == 0 || boundary.size.height == 0) {
          debugPrint(
              'captureWidgetViaOverlay: boundary has zero size (attempt $attempt). Waiting...');
          await Future.delayed(attemptDelay);
          continue;
        }

        try {
          final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          try {
            img.dispose();
          } catch (_) {}
          if (byteData == null)
            throw Exception('Failed to convert image to bytes.');
          return byteData.buffer.asUint8List();
        } on AssertionError catch (e, st) {
          debugPrint(
              'captureWidgetViaOverlay: toImage assertion (attempt $attempt): $e\n$st');
          await Future.delayed(attemptDelay);
          continue;
        } catch (e, st) {
          debugPrint(
              'captureWidgetViaOverlay: unexpected error (attempt $attempt): $e\n$st');
          await Future.delayed(attemptDelay);
          continue;
        }
      }

      throw Exception(
          'الودجت لم تُرسم بعد (needsPaint/zero-size) بعد عدة محاولات.');
    } finally {
      // remove overlay in all cases
      entry.remove();
    }
  }

  static Future<void> showReceiptPreviewDialog(
    BuildContext context,
    Uint8List pngBytes, {
    double width = 320,
  }) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black87,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'معاينة الإيصال',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: AppColorsDark.mainTextDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: Icon(Icons.close,
                            color: Theme.of(context).iconTheme.color),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: Image.memory(
                          pngBytes,
                          width: width,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('إغلاق'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// High level: capture a widget via overlay, save debug png, then show preview.
  static Future<void> printWidgetUsingOverlay(
    BuildContext context,
    Widget receiptWidget, {
    double width = 250,
    double pixelRatio = 3.0,
  }) async {
    await ensureCairoLoaded();

    Uint8List pngBytes;
    try {
      pngBytes = await captureWidgetViaOverlay(context, receiptWidget,
          width: width, pixelRatio: pixelRatio);
      // optional: save preview to system temp for debugging
      try {
        final tmp = Directory.systemTemp;
        final f = File(
            '${tmp.path}/receipt_preview_${DateTime.now().millisecondsSinceEpoch}.png');
        await f.writeAsBytes(pngBytes);
        debugPrint('Saved preview PNG: ${f.path}');
      } catch (_) {}
    } catch (e, st) {
      debugPrint('printWidgetUsingOverlay: capture failed: $e\n$st');
      rethrow;
    }

    await showReceiptPreviewDialog(context, pngBytes, width: width);
  }

  /// Backwards-compatible convenience (keeps existing API)
  static Future<void> captureAndPrint(GlobalKey key,
      {double pixelRatio = 3.0}) async {
    await ensureCairoLoaded();
    final png = await captureKeyAsPng(key, pixelRatio: pixelRatio);
    try {
      final tmp = Directory.systemTemp;
      final f = File('${tmp.path}/receipt_preview.png');
      await f.writeAsBytes(png);
      debugPrint('Saved preview PNG: ${f.path}');
    } catch (_) {}
    final context = key.currentContext;
    if (context == null) {
      throw Exception('No context found for receipt preview.');
    }
    await showReceiptPreviewDialog(context, png);
  }
}
