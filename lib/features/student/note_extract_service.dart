import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

/// What happened when text was extracted from one file.
enum NoteExtractOutcome {
  /// Text was found in the file.
  ok,

  /// The file opened fine but no text was found in it (an image
  /// with no words, a scanned PDF with no text layer, an empty
  /// text file). The sheet shows an honest empty state — never
  /// sample text.
  empty,

  /// A video file. Picking works; extracting text from video is
  /// NOT supported in this build (see the class doc). The sheet
  /// says so plainly instead of faking a result.
  videoUnsupported,

  /// The file type has no extractor (not PDF / image / text /
  /// video). The sheet says so plainly.
  typeUnsupported,
}

class NoteExtractResult {
  const NoteExtractResult({
    required this.outcome,
    this.text = '',
    required this.fileName,
  });

  final NoteExtractOutcome outcome;

  /// Extracted text (non-empty only when [outcome] is [ok]).
  final String text;
  final String fileName;
}

/// Extracts text from a picked file into a note draft.
///
/// - Images (png/jpg/jpeg/webp/heic/heif/bmp/gif): on-device OCR
///   via google_mlkit_text_recognition (Latin script, bundled —
///   no download, no Gradle change).
/// - PDF: text layer via pdfrx (PdfDocument.openFile + loadText per
///   page). A scanned/image-only PDF has no text layer and reports
///   [NoteExtractOutcome.empty].
/// - Plain text (.txt/.md/.csv): read directly as text.
/// - Video (.mp4/.mov/.avi/.mkv/.webm/.3gp): NOT supported in this
///   build. A sampled-frames + OCR pipeline needs a frame-extraction
///   plugin; the only current one (video_thumbnail 0.5.6) requires
///   Dart <3.0.0 and cannot resolve against this app's Dart 3.13.5,
///   and a hand-written MethodChannel cannot be compile-verified
///   locally (Gradle loopback is blocked in the sandbox), so a
///   failed cloud build is worse than an honest gap. The picker
///   still opens and the sheet says video extraction is not
///   supported yet — never a faked transcript.
/// - Anything else: [NoteExtractOutcome.typeUnsupported].
///
/// The OCR and PDF functions are injectable so tests can run without
/// native plugins (platform channels throw in `flutter test`).
class NoteExtractService {
  NoteExtractService({
    Future<String> Function(String path)? ocr,
    Future<String> Function(String path)? pdf,
  })  : _ocr = ocr ?? _defaultOcr,
        _pdf = pdf ?? _defaultPdf;

  final Future<String> Function(String path) _ocr;
  final Future<String> Function(String path) _pdf;

  static const imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'heic',
    'heif',
    'bmp',
    'gif',
  };

  static const videoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};

  static const textExtensions = {'txt', 'md', 'csv'};

  static String extensionOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  Future<NoteExtractResult> extract(File file) async {
    final fileName = file.path.split('/').last;
    final ext = extensionOf(file.path);
    try {
      if (ext == 'pdf') {
        final text = (await _pdf(file.path)).trim();
        return NoteExtractResult(
          outcome:
              text.isEmpty ? NoteExtractOutcome.empty : NoteExtractOutcome.ok,
          text: text,
          fileName: fileName,
        );
      }
      if (imageExtensions.contains(ext)) {
        final text = (await _ocr(file.path)).trim();
        return NoteExtractResult(
          outcome:
              text.isEmpty ? NoteExtractOutcome.empty : NoteExtractOutcome.ok,
          text: text,
          fileName: fileName,
        );
      }
      if (videoExtensions.contains(ext)) {
        return NoteExtractResult(
          outcome: NoteExtractOutcome.videoUnsupported,
          fileName: fileName,
        );
      }
      if (textExtensions.contains(ext)) {
        final text = (await file.readAsString()).trim();
        return NoteExtractResult(
          outcome:
              text.isEmpty ? NoteExtractOutcome.empty : NoteExtractOutcome.ok,
          text: text,
          fileName: fileName,
        );
      }
      return NoteExtractResult(
        outcome: NoteExtractOutcome.typeUnsupported,
        fileName: fileName,
      );
    } catch (_) {
      // A file that cannot be read or parsed reports "no text
      // found" instead of crashing — the sheet shows the honest
      // empty state for it.
      return NoteExtractResult(
        outcome: NoteExtractOutcome.empty,
        fileName: fileName,
      );
    }
  }

  static Future<String> _defaultOcr(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  static bool _pdfInitialized = false;

  static Future<String> _defaultPdf(String path) async {
    if (!_pdfInitialized) {
      await pdfrxFlutterInitialize();
      _pdfInitialized = true;
    }
    final doc = await PdfDocument.openFile(path);
    try {
      final buffer = StringBuffer();
      for (final page in doc.pages) {
        final raw = await page.loadText();
        if (raw != null && raw.fullText.isNotEmpty) {
          buffer.writeln(raw.fullText);
        }
      }
      return buffer.toString();
    } finally {
      await doc.dispose();
    }
  }
}
