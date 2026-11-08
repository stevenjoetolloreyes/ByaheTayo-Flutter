import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Rich-text helpers for notes, built on flutter_quill Delta documents.
///
/// Storage rule (Nov 8): a note's plain [Note.body] is ALWAYS the
/// document's plain text, and [Note.bodyRich] holds the Delta JSON
/// ONLY when the document actually carries formatting. Plain notes
/// keep `bodyRich == null` and render from `body` exactly as before,
/// so old notes (e.g. the "hello" note) are untouched by this change.
///
/// Highlight rule (Nov 8 readability fix): a highlight is applied
/// as background + dark ink TOGETHER, so highlighted text always
/// renders dark-on-yellow — white-on-yellow was unreadable in dark
/// mode in the preview.
///
/// The custom editor was rejected in favour of flutter_quill 11.6.0:
/// a hand-rolled editor cannot reliably handle IME composing,
/// autocorrect and backspace-on-empty-block on soft keyboards, and
/// quill's Delta JSON is the stable storage format.

/// Highlight background in dark mode (the preview's `--hl-bg`).
const String kNoteHighlightBackgroundDark = '#ffd93d';

/// Highlight background in light mode (the preview's `--hl-bg`).
const String kNoteHighlightBackgroundLight = '#ffe08a';

/// Highlight ink — dark text on the yellow background, always.
const String kNoteHighlightInk = '#1c2420';

class NoteRichText {
  /// Build a Quill document for a note: the stored Delta when the
  /// note has formatting, otherwise a plain document from [body].
  /// A corrupt stored Delta never bricks the note — it falls back
  /// to the plain body.
  static Document documentFor({
    required String body,
    List<dynamic>? bodyRich,
  }) {
    if (bodyRich != null && bodyRich.isNotEmpty) {
      try {
        return Document.fromJson(bodyRich);
      } catch (_) {
        // Fall through to the plain body.
      }
    }
    final doc = Document();
    if (body.isNotEmpty) doc.insert(0, body);
    return doc;
  }

  /// Plain text of a document, without the trailing newline Quill
  /// always appends to every document.
  static String plainText(Document doc) {
    final text = doc.toPlainText();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  /// True when the document has no text at all.
  static bool isEmpty(Document doc) => plainText(doc).trim().isEmpty;

  /// The Delta JSON to store, or null when the document has no
  /// formatting at all (so plain notes stay plain in storage).
  static List<Map<String, dynamic>>? deltaJsonIfFormatted(Document doc) {
    final json = doc.toDelta().toJson();
    return _hasFormatting(json) ? json : null;
  }

  static bool _hasFormatting(List<Map<String, dynamic>> json) {
    for (final op in json) {
      final attrs = op['attributes'];
      if (attrs is Map && attrs.isNotEmpty) return true;
    }
    return false;
  }

  /// A controller for an editable note document (the edit page).
  static QuillController editableController(Document doc) =>
      QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );

  /// A controller for a read-only note document (the view page).
  static QuillController readOnlyController(Document doc) => QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );

  /// True when the current selection (or caret) carries [key].
  static bool hasAttribute(QuillController controller, String key) =>
      controller.getSelectionStyle().attributes.containsKey(key);

  /// True when the current selection (or caret) is highlighted.
  static bool hasHighlight(QuillController controller) =>
      hasAttribute(controller, Attribute.background.key);

  /// True when the current line is a bullet list item.
  static bool hasBullet(QuillController controller) {
    final attr =
        controller.getSelectionStyle().attributes[Attribute.list.key];
    return attr?.value == 'bullet';
  }

  /// Toggle an inline format (bold / italic / underline /
  /// strikethrough) on the current selection — or on the caret, so
  /// text typed next takes the format.
  static void toggleInline(QuillController controller, Attribute attribute) {
    final style = controller.getSelectionStyle();
    if (style.attributes.containsKey(attribute.key)) {
      controller.formatSelection(Attribute.clone(attribute, null));
    } else {
      controller.formatSelection(attribute);
    }
  }

  /// Toggle the highlight. Applied as background + dark ink together
  /// (see the highlight rule above); removing it removes both.
  static void toggleHighlight(
    QuillController controller, {
    required bool darkMode,
  }) {
    final bg = darkMode
        ? kNoteHighlightBackgroundDark
        : kNoteHighlightBackgroundLight;
    if (hasHighlight(controller)) {
      controller.formatSelection(Attribute.clone(Attribute.background, null));
      controller.formatSelection(Attribute.clone(Attribute.color, null));
    } else {
      controller.formatSelection(BackgroundAttribute(bg));
      controller.formatSelection(const ColorAttribute(kNoteHighlightInk));
    }
  }

  /// Toggle a bullet list on the current line(s).
  static void toggleBullet(QuillController controller) {
    if (hasBullet(controller)) {
      controller.formatSelection(Attribute.clone(Attribute.list, null));
    } else {
      controller.formatSelection(const ListAttribute('bullet'));
    }
  }
}
