import 'dart:io';

import 'package:estudyantego/features/student/note_create_sheet.dart';
import 'package:estudyantego/features/student/note_detail_page.dart';
import 'package:estudyantego/features/student/note_extract_service.dart';
import 'package:estudyantego/features/student/note_rich_text.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quill editor throws without its delegate, so every pumped
/// app in this file carries the same delegates as the real app.
Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

Note _plainNote({String body = 'hello world'}) => Note(
      id: 'n1',
      title: 'hello',
      subject: '',
      body: body,
      favorite: false,
      updated: DateTime(2026, 11, 8),
    );

/// A controller over [doc] with [text] selected (or the caret at
/// [start] when [end] is null).
QuillController _controllerFor(
  Document doc, {
  int start = 0,
  int? end,
}) {
  return QuillController(
    document: doc,
    selection: TextSelection(
      baseOffset: start,
      extentOffset: end ?? start,
    ),
  );
}

Map<String, dynamic>? _opWithText(List<dynamic> json, String text) {
  for (final op in json) {
    if (op is Map<String, dynamic> && op['insert'] == text) return op;
  }
  return null;
}

void main() {
  group('Note.bodyRich storage', () {
    test('plain note round-trips with bodyRich null', () {
      final note = _plainNote();
      final restored = Note.fromJson(note.toJson());
      expect(restored.body, 'hello world');
      expect(restored.bodyRich, isNull);
      expect(restored.hasRichBody, isFalse);
      expect(restored.toJson().containsKey('body_rich'), isFalse);
    });

    test('rich note round-trips its Delta JSON', () {
      final delta = [
        {'insert': 'hi', 'attributes': {'bold': true}},
        {'insert': '\n'},
      ];
      final note = Note(
        id: 'n2',
        title: 'rich',
        subject: '',
        body: 'hi',
        favorite: false,
        updated: DateTime(2026, 11, 8),
        bodyRich: delta,
      );
      final restored = Note.fromJson(note.toJson());
      expect(restored.hasRichBody, isTrue);
      expect(restored.bodyRich, delta);
      expect(restored.body, 'hi');
    });

    test('old stored JSON without body_rich still loads', () {
      final restored = Note.fromJson({
        'id': 'n3',
        'title': 'old',
        'subject': '',
        'body': 'old note',
        'favorite': false,
        'updated': '2026-11-08T00:00:00.000',
      });
      expect(restored.bodyRich, isNull);
      expect(restored.hasRichBody, isFalse);
    });
  });

  group('NoteRichText', () {
    test('documentFor plain body round-trips its text', () {
      final doc = NoteRichText.documentFor(body: 'hello world');
      expect(NoteRichText.plainText(doc), 'hello world');
      expect(NoteRichText.isEmpty(doc), isFalse);
      expect(NoteRichText.deltaJsonIfFormatted(doc), isNull);
    });

    test('documentFor rich Delta round-trips its text', () {
      final doc = NoteRichText.documentFor(
        body: 'hi',
        bodyRich: [
          {'insert': 'hi', 'attributes': {'bold': true}},
          {'insert': '\n'},
        ],
      );
      expect(NoteRichText.plainText(doc), 'hi');
      expect(NoteRichText.deltaJsonIfFormatted(doc), isNotNull);
    });

    test('documentFor falls back to plain body on a corrupt Delta', () {
      final doc = NoteRichText.documentFor(
        body: 'fallback',
        bodyRich: [
          {'insert': 42},
        ],
      );
      expect(NoteRichText.plainText(doc), 'fallback');
    });

    test('bold toggle applies and removes the attribute', () {
      final doc = NoteRichText.documentFor(body: 'hello world');
      final controller = _controllerFor(doc, start: 0, end: 5);
      NoteRichText.toggleInline(controller, Attribute.bold);
      var json = controller.document.toDelta().toJson();
      expect(_opWithText(json, 'hello')?['attributes']?['bold'], isTrue);
      expect(NoteRichText.deltaJsonIfFormatted(controller.document),
          isNotNull);
      NoteRichText.toggleInline(controller, Attribute.bold);
      json = controller.document.toDelta().toJson();
      expect(_opWithText(json, 'hello')?['attributes'], isNull);
      expect(NoteRichText.deltaJsonIfFormatted(controller.document), isNull);
    });

    test('highlight applies background + dark ink together, and removes both',
        () {
      final doc = NoteRichText.documentFor(body: 'I miss you');
      final controller = _controllerFor(doc, start: 0, end: 10);
      NoteRichText.toggleHighlight(controller, darkMode: true);
      var json = controller.document.toDelta().toJson();
      final op = _opWithText(json, 'I miss you');
      // The Nov 8 readability fix: dark text on the yellow
      // highlight — never white-on-yellow.
      expect(op?['attributes']?['background'], '#ffd93d');
      expect(op?['attributes']?['color'], '#1c2420');
      NoteRichText.toggleHighlight(controller, darkMode: true);
      json = controller.document.toDelta().toJson();
      expect(_opWithText(json, 'I miss you')?['attributes'], isNull);
    });

    test('highlight uses the light-mode yellow in light mode', () {
      final doc = NoteRichText.documentFor(body: 'hi');
      final controller = _controllerFor(doc, start: 0, end: 2);
      NoteRichText.toggleHighlight(controller, darkMode: false);
      final json = controller.document.toDelta().toJson();
      expect(_opWithText(json, 'hi')?['attributes']?['background'], '#ffe08a');
      expect(_opWithText(json, 'hi')?['attributes']?['color'], '#1c2420');
    });

    test('bullet toggle applies and removes the list attribute', () {
      final doc = NoteRichText.documentFor(body: 'one\ntwo');
      final controller = _controllerFor(doc);
      NoteRichText.toggleBullet(controller);
      var json = controller.document.toDelta().toJson();
      expect(
        json.any((op) => op['attributes']?['list'] == 'bullet'),
        isTrue,
      );
      expect(NoteRichText.hasBullet(controller), isTrue);
      NoteRichText.toggleBullet(controller);
      json = controller.document.toDelta().toJson();
      expect(
        json.any((op) => op['attributes']?['list'] == 'bullet'),
        isFalse,
      );
    });
  });

  group('NoteExtractService', () {
    test('PDF goes to the PDF extractor', () async {
      final service = NoteExtractService(
        pdf: (_) async => 'pdf text',
        ocr: (_) async => throw StateError('ocr must not run'),
      );
      final result = await service.extract(File('/tmp/notes.pdf'));
      expect(result.outcome, NoteExtractOutcome.ok);
      expect(result.text, 'pdf text');
      expect(result.fileName, 'notes.pdf');
    });

    test('image goes to OCR; empty OCR means empty outcome', () async {
      final ocr = NoteExtractService(ocr: (_) async => '  ocr text  ');
      final found = await ocr.extract(File('/tmp/photo.jpg'));
      expect(found.outcome, NoteExtractOutcome.ok);
      expect(found.text, 'ocr text');

      final blank = NoteExtractService(ocr: (_) async => '   ');
      final empty = await blank.extract(File('/tmp/photo.png'));
      expect(empty.outcome, NoteExtractOutcome.empty);
      expect(empty.text, isEmpty);
    });

    test('video is honestly unsupported and never calls OCR/PDF', () async {
      final service = NoteExtractService(
        pdf: (_) async => throw StateError('pdf must not run'),
        ocr: (_) async => throw StateError('ocr must not run'),
      );
      final result = await service.extract(File('/tmp/clip.mp4'));
      expect(result.outcome, NoteExtractOutcome.videoUnsupported);
      expect(result.text, isEmpty);
    });

    test('unknown type is unsupported', () async {
      final result =
          await NoteExtractService().extract(File('/tmp/deck.pptx'));
      expect(result.outcome, NoteExtractOutcome.typeUnsupported);
    });

    test('text file is read directly', () async {
      final dir = await Directory.systemTemp.createTemp('notes_flow');
      try {
        final file = File('${dir.path}/sample.txt');
        await file.writeAsString('  hello from file  ');
        final result = await NoteExtractService().extract(file);
        expect(result.outcome, NoteExtractOutcome.ok);
        expect(result.text, 'hello from file');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('extensionOf handles upper case and missing extensions', () {
      expect(NoteExtractService.extensionOf('/a/Doc.PDF'), 'pdf');
      expect(NoteExtractService.extensionOf('/a/noext'), '');
    });
  });

  group('+ menu and Add note sheet', () {
    testWidgets('menu shows 5 items; Add notes saves a note',
        (tester) async {
      Note? created;
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                created = await showNoteCreateMenu(
                  tester.element(find.byType(ElevatedButton)),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final label in ['Add notes', 'Camera', 'Photos', 'Videos', 'Files']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Add notes'));
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'My title');
      await tester.enterText(fields.at(1), 'My body');
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(created, isNotNull);
      expect(created!.title, 'My title');
      expect(created!.body, 'My body');
      expect(created!.bodyRich, isNull);
    });

    testWidgets('Add note sheet requires a title', (tester) async {
      Note? created;
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                created = await showNoteCreateMenu(
                  tester.element(find.byType(ElevatedButton)),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Add notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pump();
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(created, isNull);
    });
  });

  group('note view and edit pages', () {
    testWidgets('plain note renders; Edit opens the edit page; Save returns it',
        (tester) async {
      Note? popped;
      await tester.pumpWidget(_wrap(
        Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                popped = await Navigator.push<Note>(
                  tester.element(find.byType(ElevatedButton)),
                  MaterialPageRoute(
                    builder: (_) => NoteDetailPage(note: _plainNote()),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsWidgets);
      expect(find.text('hello world'), findsOneWidget);
      expect(find.text('Nov 8, 2026'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit note'), findsOneWidget);
      // The preview's toolbar set.
      for (final label in [
        'Bold',
        'Highlight',
        'Italic',
        'Underline',
        'Strikethrough',
        'Bullet list',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
      }
      // The body in the edit page is rendered by the Quill editor
      // as standalone RichText (not a Text widget), so match
      // RichText too.
      expect(
        find.textContaining('hello world', findRichText: true),
        findsWidgets,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Back on the view page with the (unchanged) note.
      expect(find.text('hello world'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(popped, isNotNull);
      expect(popped!.title, 'hello');
      expect(popped!.body, 'hello world');
      expect(popped!.bodyRich, isNull);
    });

    testWidgets('highlighted text renders in the read-only view',
        (tester) async {
      final rich = Note(
        id: 'n9',
        title: 'rich',
        subject: '',
        body: 'I miss you',
        favorite: false,
        updated: DateTime(2026, 11, 8),
        bodyRich: [
          {
            'insert': 'I miss you',
            'attributes': {'background': '#ffd93d', 'color': '#1c2420'},
          },
          {'insert': '\n'},
        ],
      );
      await tester.pumpWidget(_wrap(NoteDetailPage(note: rich)));
      await tester.pumpAndSettle();
      // The read-only editor renders the text as standalone
      // RichText (not a Text widget), so match RichText too.
      expect(
        find.textContaining('I miss you', findRichText: true),
        findsWidgets,
      );
      // The rendered span carries the yellow background and the
      // dark ink (the readability fix) — walk the editor's RichText
      // spans to prove it, not just the Delta.
      var found = false;
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == 'I miss you') {
            expect(span.style?.backgroundColor, const Color(0xFFFFD93D));
            expect(span.style?.color, const Color(0xFF1C2420));
            found = true;
          }
          span.children?.forEach(walk);
        }
      }

      for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
        walk(richText.text);
      }
      expect(found, isTrue);
    });
  });
}
