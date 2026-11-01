// Tests for the Churches completion batch: sheet search + source
// filters, Places photo slot data, and grid marker clustering.
// Pure helpers only — no GoogleMap widget needed, so these run
// without a platform view. The photo slot widget itself is tested
// below with mocked Places entries (no network: the photo-present
// case asserts only that an Image widget is built, not that bytes
// load).
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _verified = [
  ChurchPlace(
    name: 'St. Paul Metropolitan Cathedral',
    lat: 17.57467,
    lng: 120.3889,
    address: 'Vigan City, Ilocos Sur',
  ),
  ChurchPlace(
    name: 'St. Mark the Evangelist Parish',
    lat: 17.79479,
    lng: 120.45627,
    address: 'Cabugao, Ilocos Sur',
  ),
];

const _places = [
  ChurchPlace(
    name: 'St. Augustine Parish Church',
    lat: 17.58109,
    lng: 120.39111,
    address: 'Bantay, Ilocos Sur',
    photoName: 'places/ChIJ1/photos/AUac1',
  ),
  ChurchPlace(
    name: 'Santa Maria Church',
    lat: 17.36684,
    lng: 120.4828,
    address: 'Santa Maria, Ilocos Sur',
  ),
];

void main() {
  group('visibleChurches search + source filters', () {
    test('empty query with All returns both lists untouched', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: '',
        filter: ChurchSourceFilter.all,
      );
      expect(visible.verified.length, 2);
      expect(visible.places.length, 2);
    });

    test('search matches by name, case-insensitive, both lists', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: 'paul',
        filter: ChurchSourceFilter.all,
      );
      expect(visible.verified.map((c) => c.name), [
        'St. Paul Metropolitan Cathedral',
      ]);
      expect(visible.places, isEmpty);
    });

    test('search does not match on address', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: 'Bantay',
        filter: ChurchSourceFilter.all,
      );
      expect(visible.verified, isEmpty);
      expect(visible.places, isEmpty);
    });

    test('Verified filter drops Places entries', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: '',
        filter: ChurchSourceFilter.verified,
      );
      expect(visible.verified.length, 2);
      expect(visible.places, isEmpty);
    });

    test('From Places filter drops verified entries', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: '',
        filter: ChurchSourceFilter.places,
      );
      expect(visible.verified, isEmpty);
      expect(visible.places.length, 2);
    });

    test('search and filter compose: query + Verified', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: 'st.',
        filter: ChurchSourceFilter.verified,
      );
      expect(visible.verified.length, 2);
      expect(visible.places, isEmpty);
    });

    test('search and filter compose: query + From Places', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: 'maria',
        filter: ChurchSourceFilter.places,
      );
      expect(visible.verified, isEmpty);
      expect(visible.places.map((c) => c.name), ['Santa Maria Church']);
    });

    test('no match yields empty lists (sheet shows empty state)', () {
      final visible = visibleChurches(
        verified: _verified,
        places: _places,
        query: 'zzz-no-such-church',
        filter: ChurchSourceFilter.all,
      );
      expect(visible.verified, isEmpty);
      expect(visible.places, isEmpty);
    });
  });

  group('Places photo parsing + photo URL', () {
    test('parsePlacesChurches keeps the first photo name', () {
      final parsed = parsePlacesChurches({
        'places': [
          {
            'displayName': {'text': 'St. Augustine Parish Church'},
            'location': {'latitude': 17.58109, 'longitude': 120.39111},
            'formattedAddress': 'Bantay, Ilocos Sur',
            'photos': [
              {'name': 'places/ChIJ1/photos/AUac1'},
              {'name': 'places/ChIJ1/photos/AUac2'},
            ],
          },
        ],
      });
      expect(parsed.length, 1);
      expect(parsed.first.photoName, 'places/ChIJ1/photos/AUac1');
    });

    test('parsePlacesChurches without photos yields null photoName', () {
      final parsed = parsePlacesChurches({
        'places': [
          {
            'displayName': {'text': 'Santa Maria Church'},
            'location': {'latitude': 17.36684, 'longitude': 120.4828},
          },
        ],
      });
      expect(parsed.length, 1);
      expect(parsed.first.photoName, isNull);
    });

    test('churchPhotoUrl builds the Places media URL', () {
      expect(
        churchPhotoUrl(_places.first, 'TESTKEY'),
        'https://places.googleapis.com/v1/places/ChIJ1/photos/AUac1'
        '/media?maxWidthPx=800&key=TESTKEY',
      );
    });

    test('churchPhotoUrl is null without photo data', () {
      expect(churchPhotoUrl(_places.last, 'TESTKEY'), isNull);
      expect(churchPhotoUrl(_verified.first, 'TESTKEY'), isNull);
    });

    test('churchPhotoUrl is null without an API key', () {
      expect(churchPhotoUrl(_places.first, ''), isNull);
    });
  });

  group('clusterChurches grid grouping', () {
    test('empty input yields no clusters', () {
      expect(clusterChurches(const [], 8), isEmpty);
    });

    test('close churches at low zoom form one cluster', () {
      final clusters = clusterChurches(const [
        ChurchPlace(name: 'A', lat: 17.57467, lng: 120.3889),
        ChurchPlace(name: 'B', lat: 17.58109, lng: 120.39111),
        ChurchPlace(name: 'C', lat: 17.59454, lng: 120.37436),
      ], 8);
      expect(clusters.length, 1);
      expect(clusters.first.count, 3);
      expect(clusters.first.isSingle, isFalse);
    });

    test('far churches stay separate at low zoom', () {
      final clusters = clusterChurches(const [
        ChurchPlace(name: 'Vigan', lat: 17.57467, lng: 120.3889),
        ChurchPlace(name: 'Laoag', lat: 18.19457, lng: 120.59334),
      ], 8);
      expect(clusters.length, 2);
      expect(clusters.every((c) => c.isSingle), isTrue);
    });

    test('cluster centroid is the average of its churches', () {
      final clusters = clusterChurches(const [
        ChurchPlace(name: 'A', lat: 17.0, lng: 120.0),
        ChurchPlace(name: 'B', lat: 17.1, lng: 120.1),
      ], 8);
      expect(clusters.length, 1);
      expect(clusters.first.lat, closeTo(17.05, 1e-9));
      expect(clusters.first.lng, closeTo(120.05, 1e-9));
    });

    test('zooming in splits a low-zoom cluster', () {
      const churches = [
        ChurchPlace(name: 'A', lat: 17.57467, lng: 120.3889),
        ChurchPlace(name: 'B', lat: 17.58109, lng: 120.39111),
      ];
      expect(clusterChurches(churches, 8).length, 1);
      expect(clusterChurches(churches, 16).length, 2);
    });

    test('a lone church is a single cluster', () {
      final clusters = clusterChurches(const [
        ChurchPlace(name: 'A', lat: 17.57467, lng: 120.3889),
      ], 8);
      expect(clusters.length, 1);
      expect(clusters.first.isSingle, isTrue);
      expect(clusters.first.count, 1);
    });
  });

  group('ChurchPhotoSlot widget', () {
    testWidgets('shows the honest empty state without photo data', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChurchPhotoSlot(
              church: ChurchPlace(
                name: 'St. Paul Metropolitan Cathedral',
                lat: 17.57467,
                lng: 120.3889,
              ),
              apiKey: 'TESTKEY',
            ),
          ),
        ),
      );
      expect(find.text('No photo available'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows an Image for a Places entry with photo data', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChurchPhotoSlot(
              church: ChurchPlace(
                name: 'St. Augustine Parish Church',
                lat: 17.58109,
                lng: 120.39111,
                photoName: 'places/ChIJ1/photos/AUac1',
              ),
              apiKey: 'TESTKEY',
            ),
          ),
        ),
      );
      // The Image widget is built (bytes load asynchronously and
      // are not awaited here); a failed load falls back to the
      // empty state via errorBuilder at runtime.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('shows the empty state when the key is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChurchPhotoSlot(
              church: ChurchPlace(
                name: 'St. Augustine Parish Church',
                lat: 17.58109,
                lng: 120.39111,
                photoName: 'places/ChIJ1/photos/AUac1',
              ),
              apiKey: '',
            ),
          ),
        ),
      );
      expect(find.text('No photo available'), findsOneWidget);
    });
  });
}
