import 'package:flutter/material.dart';
import '../top_popup.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'note_rich_text.dart';
import 'student_data.dart';

/// Full-screen note view page — a NEW PAGE (Steven's Nov 8, 21:14
/// clarification: "yung notes Gagawa ka ng bagong pages"), NOT a
/// dialog or sheet. Matches the preview: back button + "Note" title
/// + Edit button; title 20px bold, date 12px, body 14.5px with 1.65
/// line height; slide-from-right + fade via the standard
/// MaterialPageRoute.
///
/// Returns the updated [Note] when the note was edited (through the
/// edit page), or null when nothing changed. The caller saves it.
/// Plain notes render from [Note.body] exactly as before; formatted
/// notes render the read-only Quill document (highlight = dark text
/// on yellow, per the Nov 8 readability fix).
class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.note});

  final Note note;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late Note _note;
  QuillController? _richController;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _richController = _controllerFor(_note);
  }

  QuillController? _controllerFor(Note note) {
    if (!note.hasRichBody) return null;
    return NoteRichText.readOnlyController(
      NoteRichText.documentFor(body: note.body, bodyRich: note.bodyRich),
    );
  }

  @override
  void dispose() {
    _richController?.dispose();
    super.dispose();
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.push<Note>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditPage(note: _note)),
    );
    if (updated == null) return;
    _richController?.dispose();
    setState(() {
      _note = updated;
      _richController = _controllerFor(updated);
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Back (system or AppBar) returns the updated note when the
    // note was edited, null otherwise — the caller saves it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed ? _note : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Note'),
          actions: [
            TextButton.icon(
              onPressed: _openEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _note.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatDate(_note.updated),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 16),
              if (_richController != null)
                QuillEditor.basic(
                  controller: _richController!,
                  config: const QuillEditorConfig(scrollable: false),
                )
              else if (_note.body.isNotEmpty)
                Text(
                  _note.body,
                  style: const TextStyle(fontSize: 14.5, height: 1.65),
                )
              else
                Text(
                  'No content.',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen note edit page — a NEW PAGE (same Nov 8
/// clarification). Matches the preview: title input (17px bold),
/// formatting toolbar (Bold, Highlight, Italic, Underline,
/// Strikethrough, bullet list), body editor, Save action.
/// Highlight renders dark text on yellow (the Nov 8 fix), in both
/// the editor and the view page.
///
/// Returns the updated [Note] on Save, or null when the user backs
/// out without saving (changes are discarded, as in the old form).
/// The plain [Note.body] is always kept in sync with the document,
/// and [Note.bodyRich] is stored only when the document actually
/// carries formatting — so a note edited without any formatting
/// stays a plain note in storage.
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, required this.note});

  final Note note;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late final TextEditingController _title;
  late final QuillController _controller;
  late final FocusNode _editorFocus;
  late final ScrollController _editorScroll;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _controller = NoteRichText.editableController(
      NoteRichText.documentFor(
        body: widget.note.body,
        bodyRich: widget.note.bodyRich,
      ),
    );
    // Start at the end of the existing text, ready to keep writing.
    _controller.moveCursorToEnd();
    _editorFocus = FocusNode();
    _editorScroll = ScrollController();
  }

  @override
  void dispose() {
    _title.dispose();
    _controller.dispose();
    _editorFocus.dispose();
    _editorScroll.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      TopPopup.show(context, message: 'Enter a title.');
      return;
    }
    final doc = _controller.document;
    Navigator.pop(
      context,
      Note(
        id: widget.note.id,
        title: title,
        subject: widget.note.subject,
        body: NoteRichText.plainText(doc),
        favorite: widget.note.favorite,
        updated: DateTime.now(),
        bodyRich: NoteRichText.deltaJsonIfFormatted(doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit note'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
            ),
          ),
          // Formatting toolbar — the preview's set: Bold,
          // Highlight, Italic, Underline, Strikethrough, bullet
          // list. Buttons show their active state from the current
          // selection (or caret).
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Bold',
                      active: NoteRichText.hasAttribute(
                          _controller, Attribute.bold.key),
                      onPressed: () => NoteRichText.toggleInline(
                          _controller, Attribute.bold),
                      child: Text(
                        'B',
                        style: _toolTextStyle(scheme,
                            active: NoteRichText.hasAttribute(
                                _controller, Attribute.bold.key),
                            bold: true),
                      ),
                    ),
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Highlight',
                      active: NoteRichText.hasHighlight(_controller),
                      onPressed: () => NoteRichText.toggleHighlight(
                          _controller, darkMode: darkMode),
                      child: Icon(
                        Icons.highlight,
                        size: 20,
                        color: NoteRichText.hasHighlight(_controller)
                            ? scheme.primary
                            : null,
                      ),
                    ),
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Italic',
                      active: NoteRichText.hasAttribute(
                          _controller, Attribute.italic.key),
                      onPressed: () => NoteRichText.toggleInline(
                          _controller, Attribute.italic),
                      child: Text(
                        'I',
                        style: _toolTextStyle(scheme,
                            active: NoteRichText.hasAttribute(
                                _controller, Attribute.italic.key),
                            italic: true),
                      ),
                    ),
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Underline',
                      active: NoteRichText.hasAttribute(
                          _controller, Attribute.underline.key),
                      onPressed: () => NoteRichText.toggleInline(
                          _controller, Attribute.underline),
                      child: Text(
                        'U',
                        style: _toolTextStyle(scheme,
                            active: NoteRichText.hasAttribute(
                                _controller, Attribute.underline.key),
                            underline: true),
                      ),
                    ),
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Strikethrough',
                      active: NoteRichText.hasAttribute(
                          _controller, Attribute.strikeThrough.key),
                      onPressed: () => NoteRichText.toggleInline(
                          _controller, Attribute.strikeThrough),
                      child: Text(
                        'S',
                        style: _toolTextStyle(scheme,
                            active: NoteRichText.hasAttribute(
                                _controller, Attribute.strikeThrough.key),
                            strikeThrough: true),
                      ),
                    ),
                    _toolButton(
                      scheme: scheme,
                      tooltip: 'Bullet list',
                      active: NoteRichText.hasBullet(_controller),
                      onPressed: () => NoteRichText.toggleBullet(_controller),
                      child: Icon(
                        Icons.format_list_bulleted,
                        size: 20,
                        color: NoteRichText.hasBullet(_controller)
                            ? scheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: QuillEditor.basic(
                controller: _controller,
                focusNode: _editorFocus,
                scrollController: _editorScroll,
                config: const QuillEditorConfig(
                  autoFocus: true,
                  placeholder: 'Write your note…',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _toolTextStyle(
    ColorScheme scheme, {
    required bool active,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikeThrough = false,
  }) {
    return TextStyle(
      fontSize: 16,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: underline
          ? TextDecoration.underline
          : strikeThrough
              ? TextDecoration.lineThrough
              : TextDecoration.none,
      color: active ? scheme.primary : null,
    );
  }

  /// A 38×34 toolbar button (the preview's size) with a tinted
  /// background when its format is active.
  Widget _toolButton({
    required ColorScheme scheme,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 38,
        height: 34,
        child: Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
