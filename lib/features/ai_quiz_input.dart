// Picking study material for AI quiz generation: camera, gallery,
// documents.
//
// - Camera / Picture use image_picker; Documents uses file_picker.
// - Returns null when the user cancels. Throws a [FormatException]
//   with a user-facing message on permission denial or unsupported
//   files — the screen shows that message, never a crash.
// - No OCR here and no fake results: picked bytes go straight to
//   Gemini through ai_quiz_service, which reads them multimodally.
// - Docx is deliberately NOT supported in v1: it is a zip of XML,
//   and extracting its text cleanly needs archive + XML parsing
//   that does not belong in this first version. The picker dialog
//   itself only offers the supported extensions, so docx cannot
//   even be picked; [mimeTypeForExtension] is a second line of
//   defense for callers that bypass the dialog.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'ai_quiz_service.dart';

/// The three input sources offered on the generate screen.
enum AiQuizInputSource { camera, gallery, documents }

/// What a pick produced. Either [attachments] holds media for the
/// multimodal path, or [text] holds decoded plain-text content for
/// the existing text path — never both, never neither on success.
class AiQuizPickedInput {
  const AiQuizPickedInput({
    required this.label,
    this.attachments = const [],
    this.text,
  });

  final String label;
  final List<AiQuizAttachment> attachments;
  final String? text;

  bool get hasMedia => attachments.isNotEmpty;
  bool get hasText => text != null && text!.trim().isNotEmpty;
}

/// Extensions the Documents picker offers. Images + PDF go to Gemini
/// as inline data; txt/md are read as text and reuse the text path.
const List<String> kAiQuizDocumentExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'pdf',
  'txt',
  'md',
];

/// MIME type for a file extension, or null when unsupported.
/// Camera/gallery images fall back to image/jpeg only when the
/// extension is unknown — the bytes are known to be an image there.
/// Documents get no fallback: unknown means unsupported.
String? mimeTypeForExtension(String extension, {bool fromCamera = false}) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'md':
      return 'text/plain';
    default:
      return fromCamera ? 'image/jpeg' : null;
  }
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1);
}

/// Picks study material for one input source. Null = user cancelled.
Future<AiQuizPickedInput?> pickQuizInput(AiQuizInputSource source) async {
  try {
    switch (source) {
      case AiQuizInputSource.camera:
        return await _pickImage(ImageSource.camera);
      case AiQuizInputSource.gallery:
        return await _pickImage(ImageSource.gallery);
      case AiQuizInputSource.documents:
        return await _pickDocument();
    }
  } on PlatformException catch (e) {
    throw FormatException(_friendlyPlatformError(e));
  }
}

String _friendlyPlatformError(PlatformException e) {
  final code = e.code.toLowerCase();
  if (code.contains('denied') || code.contains('permission')) {
    return 'Permission denied — allow camera and photo access to '
        'use this, then try again.';
  }
  return 'Could not pick that file. Try again.';
}

Future<AiQuizPickedInput?> _pickImage(ImageSource imageSource) async {
  final picked = await ImagePicker().pickImage(
    source: imageSource,
    imageQuality: 85,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final mime =
      mimeTypeForExtension(_extensionOf(picked.name), fromCamera: true)!;
  return AiQuizPickedInput(
    label: picked.name,
    attachments: [AiQuizAttachment(mimeType: mime, bytes: bytes)],
  );
}

Future<AiQuizPickedInput?> _pickDocument() async {
  // file_picker 13 API: pickFile returns one PlatformFile (null on
  // cancel); bytes come from readAsBytes, not a withData flag.
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: kAiQuizDocumentExtensions,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final extension = _extensionOf(file.name);
  final mime = mimeTypeForExtension(extension);
  if (mime == null) {
    throw const FormatException(
      'That file type is not supported yet — pick an image, a PDF, '
      'or a plain-text file.',
    );
  }
  if (mime == 'text/plain') {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
        'That text file could not be read. Try a different file.',
      );
    }
    if (text.trim().isEmpty) {
      throw const FormatException('That text file is empty.');
    }
    return AiQuizPickedInput(label: file.name, text: text);
  }
  return AiQuizPickedInput(
    label: file.name,
    attachments: [AiQuizAttachment(mimeType: mime, bytes: bytes)],
  );
}
