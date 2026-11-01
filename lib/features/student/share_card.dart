// Share a rendered card widget as a PNG image (quotes, verses).
// Falls back to plain-text sharing when image capture fails, so the
// button always does something real.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareBoundaryAsImage({
  required GlobalKey boundaryKey,
  required String filename,
  required String fallbackText,
}) async {
  try {
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('no boundary');
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('no bytes');
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (_) {
    await SharePlus.instance.share(ShareParams(text: fallbackText));
  }
}

/// The styled card rendered for image sharing: emerald background,
/// white text, app name footer. Wrap it in RepaintBoundary with the
/// key passed to [shareBoundaryAsImage].
Widget shareCardContent({
  required String body,
  required String attribution,
  required String footer,
}) {
  return Container(
    width: 320,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF14532D),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.format_quote, color: Colors.white54, size: 32),
        const SizedBox(height: 12),
        Text(
          body,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          attribution,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          footer,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
  );
}
