import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'note_extract_service.dart';
import 'student_data.dart';

/// The Notes + menu (the preview's 5-item sheet) and the flows it
/// opens: Add notes (bottom sheet), Camera / Photos / Videos / Files
/// (pick → Extract → draft sheet → Save as note).
///
/// [showNoteCreateMenu] returns the created [Note], or null when the
/// user cancels at any step. The caller saves it. Add note stays a
/// bottom sheet, per the preview and Steven's Nov 8 clarification
/// (view/edit are the new PAGES; Add stays a sheet).
Future<Note?> showNoteCreateMenu(
  BuildContext context, {
  NoteExtractService? extractService,
}) async {
  final choice = await showModalBottomSheet<_NoteCreateChoice>(
    context: context,
    barrierColor: const Color.fromRGBO(8, 12, 10, 0.3),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _NoteCreateMenuSheet(),
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case _NoteCreateChoice.addNote:
      return _showAddNoteSheet(context);
    case _NoteCreateChoice.camera:
      return _pickAndExtract(
          context, _NoteSource.camera, extractService ?? NoteExtractService());
    case _NoteCreateChoice.photos:
      return _pickAndExtract(
          context, _NoteSource.photos, extractService ?? NoteExtractService());
    case _NoteCreateChoice.videos:
      return _pickAndExtract(
          context, _NoteSource.videos, extractService ?? NoteExtractService());
    case _NoteCreateChoice.files:
      return _pickAndExtract(
          context, _NoteSource.files, extractService ?? NoteExtractService());
  }
}

enum _NoteCreateChoice { addNote, camera, photos, videos, files }

enum _NoteSource { camera, photos, videos, files }

/// The 5-item menu sheet. Items fade + slide in with a 40ms
/// stagger (the preview's animation); the FAB rotates 45° while
/// the menu is open (handled by the caller, which sets its rotation
/// state around this call).
class _NoteCreateMenuSheet extends StatefulWidget {
  const _NoteCreateMenuSheet();

  @override
  State<_NoteCreateMenuSheet> createState() => _NoteCreateMenuSheetState();
}

class _NoteCreateMenuSheetState extends State<_NoteCreateMenuSheet> {
  static const _entries = [
    (
      _NoteCreateChoice.addNote,
      Icons.note_add_outlined,
      'Add notes',
      'Write a new note',
    ),
    (
      _NoteCreateChoice.camera,
      Icons.photo_camera_outlined,
      'Camera',
      'Take a photo and extract its text',
    ),
    (
      _NoteCreateChoice.photos,
      Icons.photo_library_outlined,
      'Photos',
      'Pick a photo and extract its text',
    ),
    (
      _NoteCreateChoice.videos,
      Icons.videocam_outlined,
      'Videos',
      'Pick a video',
    ),
    (
      _NoteCreateChoice.files,
      Icons.folder_outlined,
      'Files',
      'Pick a PDF, image or text file',
    ),
  ];

  final _shown = List<bool>.filled(_entries.length, false);

  @override
  void initState() {
    super.initState();
    // Staggered entrance: each item starts 40ms after the previous.
    for (var i = 0; i < _entries.length; i++) {
      Future.delayed(Duration(milliseconds: 40 * i), () {
        if (mounted) setState(() => _shown[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A shrink-wrapped ListView (not a Column): the 5 tall items
    // overflow a short viewport (landscape phone, small screen) —
    // the list scrolls instead of overflowing.
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _entries.length; i++)
          AnimatedOpacity(
            opacity: _shown[i] ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedSlide(
              offset: _shown[i] ? Offset.zero : const Offset(0, 0.15),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _entries[i].$2,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(_entries[i].$3),
                subtitle: Text(_entries[i].$4),
                onTap: () => Navigator.pop(context, _entries[i].$1),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Add note bottom sheet (the preview: Title + Note, Cancel
/// flex 1 outlined + Save flex 2 green, grab handle).
Future<Note?> _showAddNoteSheet(BuildContext context) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _AddNoteSheet(),
  );
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet();

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title.')),
      );
      return;
    }
    Navigator.pop(
      context,
      Note(
        id: newId(),
        title: _title.text.trim(),
        subject: '',
        body: _body.text,
        favorite: false,
        updated: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add note',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: 'TITLE',
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            decoration: InputDecoration(
              labelText: 'NOTE',
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
              hintText: 'Write your note here…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary),
              ),
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save note'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick a file from [source], extract its text, and let the user
/// review/edit the draft before saving. Returns the saved note, or
/// null when the user cancels the picker, the extraction, or the
/// draft sheet.
Future<Note?> _pickAndExtract(
  BuildContext context,
  _NoteSource source,
  NoteExtractService service,
) async {
  File? file;
  switch (source) {
    case _NoteSource.camera:
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked != null) file = File(picked.path);
    case _NoteSource.photos:
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null) file = File(picked.path);
    case _NoteSource.videos:
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked != null) file = File(picked.path);
    case _NoteSource.files:
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'heic',
          'heif',
          'bmp',
          'gif',
          'mp4',
          'mov',
          'avi',
          'mkv',
          'webm',
          'txt',
          'md',
          'csv',
        ],
      );
      if (picked != null && picked.path != null) file = File(picked.path!);
  }
  if (file == null) return null; // User cancelled the picker.
  if (!context.mounted) return null;
  final result = await showDialog<NoteExtractResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExtractProgressDialog(
      fileName: file!.path.split('/').last,
      extract: () => service.extract(file!),
    ),
  );
  if (result == null || !context.mounted) return null;
  return _showExtractDraftSheet(context, file, result);
}

/// The extracting state (the preview: spinner + "Extracting text
/// from X…" + progress bar). The bar is indeterminate — it
/// runs for the REAL extraction duration, with no fake 1.4s delay.
/// Starts the extraction once in initState and pops with the result.
class _ExtractProgressDialog extends StatefulWidget {
  const _ExtractProgressDialog({
    required this.fileName,
    required this.extract,
  });

  final String fileName;
  final Future<NoteExtractResult> Function() extract;

  @override
  State<_ExtractProgressDialog> createState() => _ExtractProgressDialogState();
}

class _ExtractProgressDialogState extends State<_ExtractProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.extract().then(
      (result) {
        if (mounted) Navigator.pop(context, result);
      },
      onError: (_) {
        // The service catches its own failures, but a rejected
        // future must never leave this dialog hanging.
        if (mounted) {
          Navigator.pop(
            context,
            NoteExtractResult(
              outcome: NoteExtractOutcome.empty,
              fileName: widget.fileName,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Extracting text from ${widget.fileName}…'),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

/// The extract draft sheet (the preview: file chip + "Extracted
/// text" box + Cancel / Save as note). The extracted text is
/// editable — the user reviews it before saving. When no text was
/// found (or the file type / video is unsupported), the sheet shows
/// the honest reason instead of a draft.
Future<Note?> _showExtractDraftSheet(
  BuildContext context,
  File file,
  NoteExtractResult result,
) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ExtractDraftSheet(file: file, result: result),
  );
}

class _ExtractDraftSheet extends StatefulWidget {
  const _ExtractDraftSheet({required this.file, required this.result});

  final File file;
  final NoteExtractResult result;

  @override
  State<_ExtractDraftSheet> createState() => _ExtractDraftSheetState();
}

class _ExtractDraftSheetState extends State<_ExtractDraftSheet> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.result.text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _titleFromFile {
    final name = widget.result.fileName;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return base.isEmpty ? 'Extracted note' : base;
  }

  void _save() {
    Navigator.pop(
      context,
      Note(
        id: newId(),
        title: _titleFromFile,
        subject: '',
        body: _text.text,
        favorite: false,
        updated: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = widget.result;
    final canSave = result.outcome == NoteExtractOutcome.ok;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // File chip.
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (canSave) ...[
            const Text(
              'Extracted text',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.primary),
                  ),
                ),
              ),
            ),
          ] else
            Text(
              switch (result.outcome) {
                NoteExtractOutcome.empty =>
                  'No text was found in this file. Try a different file — scanned images and PDFs without a text layer have nothing to extract.',
                NoteExtractOutcome.videoUnsupported =>
                  'Text extraction from video isn\'t supported yet. Choose an image, PDF, or text file.',
                NoteExtractOutcome.typeUnsupported =>
                  'This file type isn\'t supported for text extraction. Choose a PDF, image, or text file.',
                NoteExtractOutcome.ok => '',
              },
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              if (canSave) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save as note'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
