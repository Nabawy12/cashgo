// print_service.dart
// PrintService: capture RepaintBoundary -> PNG -> pdf -> printing (with Overlay capture)
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

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

  /// Capture a RepaintBoundary referenced by [key] into PNG bytes.
  /// This keeps the previous behavior for cases where the widget is already painted.
  static Future<Uint8List> captureKeyAsPng(GlobalKey key, {double pixelRatio = 3.0}) async {
    const int maxAttempts = 20;
    const Duration attemptDelay = Duration(milliseconds: 150);
    const Duration extraDelayAfterFrame = Duration(milliseconds: 40);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      await Future.delayed(extraDelayAfterFrame);

      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null) {
        debugPrint('captureKeyAsPng: renderObject == null (attempt $attempt)');
        if (attempt == maxAttempts - 1) throw Exception('RepaintBoundary غير موجود/لم يُنشأ بعد.');
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
        debugPrint('captureKeyAsPng: boundary stillNeedsPaint == true (attempt $attempt). Waiting...');
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
        debugPrint('captureKeyAsPng unexpected error (attempt $attempt): $e\n$st');
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
          debugPrint('captureWidgetViaOverlay: renderObject == null (attempt $attempt)');
          await Future.delayed(attemptDelay);
          continue;
        }

        if (renderObject is! RenderRepaintBoundary) {
          throw Exception('Widget wrapped by key is not a RenderRepaintBoundary.');
        }

        bool stillNeedsPaint = false;
        assert(() {
          stillNeedsPaint = (renderObject as RenderObject).debugNeedsPaint;
          return true;
        }());

        if (stillNeedsPaint) {
          debugPrint('captureWidgetViaOverlay: boundary stillNeedsPaint == true (attempt $attempt). Waiting...');
          await Future.delayed(attemptDelay);
          continue;
        }

        final boundary = renderObject as RenderRepaintBoundary;

        if (boundary.size.width == 0 || boundary.size.height == 0) {
          debugPrint('captureWidgetViaOverlay: boundary has zero size (attempt $attempt). Waiting...');
          await Future.delayed(attemptDelay);
          continue;
        }

        try {
          final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          try {
            img.dispose();
          } catch (_) {}
          if (byteData == null) throw Exception('Failed to convert image to bytes.');
          return byteData.buffer.asUint8List();
        } on AssertionError catch (e, st) {
          debugPrint('captureWidgetViaOverlay: toImage assertion (attempt $attempt): $e\n$st');
          await Future.delayed(attemptDelay);
          continue;
        } catch (e, st) {
          debugPrint('captureWidgetViaOverlay: unexpected error (attempt $attempt): $e\n$st');
          await Future.delayed(attemptDelay);
          continue;
        }
      }

      throw Exception('الودجت لم تُرسم بعد (needsPaint/zero-size) بعد عدة محاولات.');
    } finally {
      // remove overlay in all cases
      entry.remove();
    }
  }

  static Future<void> printPng(Uint8List pngBytes, {PdfPageFormat? pageFormat}) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat ?? PdfPageFormat.standard,
        margin: pw.EdgeInsets.all(2 * PdfPageFormat.mm),
        build: (ctx) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.fitWidth)),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  /// High level: capture a widget via overlay, save debug png, then print
  static Future<void> printWidgetUsingOverlay(
      BuildContext context,
      Widget receiptWidget, {
        double width = 250,
        double pixelRatio = 3.0,
        PdfPageFormat? pageFormat,
      }) async {
    await ensureCairoLoaded();

    Uint8List pngBytes;
    try {
      pngBytes = await captureWidgetViaOverlay(context, receiptWidget, width: width, pixelRatio: pixelRatio);
      // optional: save preview to system temp for debugging
      try {
        final tmp = Directory.systemTemp;
        final f = File('${tmp.path}/receipt_preview_${DateTime.now().millisecondsSinceEpoch}.png');
        await f.writeAsBytes(pngBytes);
        debugPrint('Saved preview PNG: ${f.path}');
      } catch (_) {}
    } catch (e, st) {
      debugPrint('printWidgetUsingOverlay: capture failed: $e\n$st');
      rethrow;
    }

    await printPng(pngBytes, pageFormat: pageFormat ?? PdfPageFormat.roll80);
  }

  /// Backwards-compatible convenience (keeps existing API)
  static Future<void> captureAndPrint(GlobalKey key, {double pixelRatio = 3.0}) async {
    await ensureCairoLoaded();
    final png = await captureKeyAsPng(key, pixelRatio: pixelRatio);
    try {
      final tmp = Directory.systemTemp;
      final f = File('${tmp.path}/receipt_preview.png');
      await f.writeAsBytes(png);
      debugPrint('Saved preview PNG: ${f.path}');
    } catch (_) {}
    await printPng(png);
  }
}
