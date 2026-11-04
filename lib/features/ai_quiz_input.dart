// Picking study material for AI quiz generation: camera, gallery,
// documents.
//
// - Camera / Picture use image_picker; Documents uses file_picker.
// - Returns null when the user cancels. Throws a [FormatException]
//   with a user-facing message on permission denial or unsupported
//   files — the screen shows that message, never a crash.
// - No OCR here and no fake results: picked bytes go straight to
//   Gemini through ai_quiz_service, which reads them multimodally.
// - Docx IS supported by a minimal client-side extractor below
//   ([extractDocxText]): a docx is a zip of XML, so the extractor
//   reads word/document.xml from the zip (stored or raw-deflate
//   via dart:io) and joins its <w:t> text nodes. No new package,
//   no backend, and no invented text: an unparseable docx throws
//   a FormatException with a user-facing message instead. The old
//   binary .doc format is still NOT supported and is rejected.
// - Doc (binary) is deliberately NOT supported: it is not XML and
//   cannot be read this way; [mimeTypeForExtension] is a second
//   line of defense for callers that bypass the dialog.
import 'dart:convert';
import 'dart:io';

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
  'docx',
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
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.'
          'wordprocessingml.document';
    default:
      return fromCamera ? 'image/jpeg' : null;
  }
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1);
}

int _zipU16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _zipU32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

String _unescapeXmlText(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Extracts the readable text from a .docx file (a zip containing
/// word/document.xml). Pure client-side: no package, no backend.
/// Throws a [FormatException] with a user-facing message when the
/// file is not a valid zip, has no document.xml, uses an
/// unsupported compression method, or yields no readable text —
/// callers must show that message and preserve the file/settings
/// for retry, never present invented text as extracted content.
String extractDocxText(Uint8List bytes) {
  const invalid =
      'That .docx file could not be read. Try a different file.';
  // Find the End Of Central Directory record (last 64 KiB at most).
  var eocd = -1;
  final searchStart = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var i = bytes.length - 22; i >= searchStart; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException(invalid);
  final cdOffset = _zipU32(bytes, eocd + 16);
  final cdCount = _zipU16(bytes, eocd + 10);
  var offset = cdOffset;
  var found = false;
  var method = 0;
  var compressedSize = 0;
  var localHeaderOffset = 0;
  for (var entry = 0; entry < cdCount; entry++) {
    if (offset + 46 > bytes.length ||
        _zipU32(bytes, offset) != 0x02014b50) {
      throw const FormatException(invalid);
    }
    final nameLength = _zipU16(bytes, offset + 28);
    final extraLength = _zipU16(bytes, offset + 30);
    final commentLength = _zipU16(bytes, offset + 32);
    final nameStart = offset + 46;
    final nameEnd = nameStart + nameLength;
    if (nameEnd > bytes.length) throw const FormatException(invalid);
    final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
    if (name == 'word/document.xml') {
      method = _zipU16(bytes, offset + 10);
      compressedSize = _zipU32(bytes, offset + 20);
      localHeaderOffset = _zipU32(bytes, offset + 42);
      found = true;
      break;
    }
    offset = nameEnd + extraLength + commentLength;
  }
  if (!found) {
    throw const FormatException(
      'That .docx file does not contain readable document text.',
    );
  }
  if (localHeaderOffset + 30 > bytes.length ||
      _zipU32(bytes, localHeaderOffset) != 0x04034b50) {
    throw const FormatException(invalid);
  }
  final localNameLength = _zipU16(bytes, localHeaderOffset + 26);
  final localExtraLength = _zipU16(bytes, localHeaderOffset + 28);
  final dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength;
  final dataEnd = dataStart + compressedSize;
  if (dataEnd > bytes.length) throw const FormatException(invalid);
  final compressed = bytes.sublist(dataStart, dataEnd);
  final List<int> xmlBytes;
  if (method == 0) {
    xmlBytes = compressed;
  } else if (method == 8) {
    try {
      xmlBytes = ZLibDecoder(raw: true).convert(compressed);
    } catch (_) {
      throw const FormatException(invalid);
    }
  } else {
    throw const FormatException(invalid);
  }
  String xml;
  try {
    xml = utf8.decode(xmlBytes);
  } catch (_) {
    throw const FormatException(invalid);
  }
  // One paragraph at a time: <w:t> nodes inside a paragraph join
  // without a separator; paragraphs join with a newline.
  final paragraphs = <String>[];
  for (final paragraph in xml.split('</w:p>')) {
    final texts = <String>[];
    for (final match in RegExp(r'<w:t[^>]*>(.*?)</w:t>')
        .allMatches(paragraph)) {
      texts.add(_unescapeXmlText(match.group(1) ?? ''));
    }
    final joined = texts.join('');
    if (joined.trim().isNotEmpty) paragraphs.add(joined);
  }
  final text = paragraphs.join('\n');
  if (text.trim().isEmpty) {
    throw const FormatException(
      'No readable text could be extracted from that .docx file.',
    );
  }
  return text;
}

/// Picks study material for one input source. Null = user cancelled.
Future<AiQuizPickedInput?> pickQuizInput(AiQuizInputSource source) async {
  try {
    switch (source) {
      case AiQuizInputSource.camera:
        return await _pickImage(ImageSource.camera);
      case AiQuizInputSource.gallery:
        return await _pickGalleryImages();
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

Future<AiQuizPickedInput?> _pickGalleryImages() async {
  final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
  if (picked.isEmpty) return null;
  final attachments = <AiQuizAttachment>[];
  for (final file in picked) {
    final bytes = await file.readAsBytes();
    attachments.add(AiQuizAttachment(
      mimeType:
          mimeTypeForExtension(_extensionOf(file.name), fromCamera: true)!,
      bytes: bytes,
    ));
  }
  if (attachments.length == 1) {
    return AiQuizPickedInput(
      label: picked.single.name,
      attachments: attachments,
    );
  }
  return AiQuizPickedInput(
    label: '${attachments.length} images',
    attachments: attachments,
  );
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
      'a plain-text file, or a .docx file.',
    );
  }
  if (extension.toLowerCase() == 'docx') {
    final String text;
    try {
      text = extractDocxText(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'That .docx file could not be read. Try a different file.',
      );
    }
    if (text.trim().isEmpty) {
      throw const FormatException(
        'No readable text could be extracted from that .docx file.',
      );
    }
    return AiQuizPickedInput(label: file.name, text: text);
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
