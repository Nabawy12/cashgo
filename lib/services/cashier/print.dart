// PrintService: capture RepaintBoundary -> PNG -> pdf -> printing
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';

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

  static Future<Uint8List> captureKeyAsPng(GlobalKey key, {double pixelRatio = 3.0}) async {
    const int maxAttempts = 12;
    const Duration attemptDelay = Duration(milliseconds: 120);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final Completer<void> frameCompleter = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!frameCompleter.isCompleted) frameCompleter.complete();
      });
      await Future.delayed(const Duration(milliseconds: 20));
      await frameCompleter.future;

      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null) {
        if (attempt == maxAttempts - 1) throw Exception('RepaintBoundary غير موجود/لم يُنشأ بعد.');
        await Future.delayed(attemptDelay);
        continue;
      }
      if (renderObject is! RenderRepaintBoundary) {
        throw Exception('العنصر المرتبط بالمفتاح ليس RenderRepaintBoundary.');
      }
      final boundary = renderObject as RenderRepaintBoundary;
      try {
        final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) throw Exception('فشل تحويل الصورة إلى بايت.');
        return byteData.buffer.asUint8List();
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        await Future.delayed(attemptDelay);
      }
    }
    throw Exception('فشل التقاط الصورة بعد عدة محاولات.');
  }

  static Future<void> printPng(Uint8List pngBytes, {PdfPageFormat? pageFormat}) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat ?? PdfPageFormat.roll80,
        margin: pw.EdgeInsets.all(2 * PdfPageFormat.mm),
        build: (ctx) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.fitWidth)),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static Future<void> captureAndPrint(GlobalKey key, {double pixelRatio = 3.0}) async {
    await ensureCairoLoaded();
    final png = await captureKeyAsPng(key, pixelRatio: pixelRatio);
    // optional: save temp file for debugging (wrapped in try)
    try {
      final tmp = Directory.systemTemp;
      final f = File('${tmp.path}/receipt_preview.png');
      await f.writeAsBytes(png);
      debugPrint('Saved preview PNG: ${f.path}');
    } catch (_) {}
    await printPng(png);
  }
}
