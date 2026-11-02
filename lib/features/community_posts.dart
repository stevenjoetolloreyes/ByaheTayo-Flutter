// Community posts in the Communities tab.
//
// TWO KINDS, always labeled: SHARED posts live in Firestore
// (collection `community_posts`) and are visible to other users once
// approved; LOCAL posts live in SharedPreferences ON THIS DEVICE ONLY
// and are never uploaded. The UI labels every card "Shared post" or
// "Local post" and says which is which. Like / Dislike / Comment live
// on approved shared posts (see community_interactions.dart) and
// device-locally on local posts; no map-preview thumbnails (no
// static-map source).
// "View on map" jumps the real Map tab to the post's hub (a real hub,
// never free text); "View Route" opens a details view of the post
// itself.
//
// APPROVAL (admin-only, see admin_access.dart): every new submission
// starts Pending and is badged "Pending verification". The in-app Post
// approvals screen (opened from the Communities tab) lets allowlisted
// admins approve or reject submissions; only approved items are badged
// "Published" and shown to all users. Rejected items are hidden from
// the main list and stay visible in the admin screen until deleted.
// Local posts keep their old device-only approval behavior; the sample
// CTransco submission stays local-only and is never uploaded.
//
// A route IS its From → To: the form asks for From and To, and the
// stored routeName is derived from them ("From → To"). Older posts
// saved before From/To existed keep their free-text routeName and
// still load; their cards show that title.
//
// Vehicle types are the 8 categories in vehicle_categories.dart,
// stored as their stable ids (e.g. 'modern-jeepney'). Older posts
// stored the old chip strings ('Jeepney', 'Bus', ...); those strings
// are kept verbatim in storage and mapped for display only.
//
// Davao data is NOT copied: route names, hubs, vehicles, and fares here
// come from the user and from EstudyanteGO's own 14 hubs.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vehicle_categories.dart';

/// SharedPreferences key for the local-only post list.
const communityPostsKey = 'byahetayo_community_posts';

/// SharedPreferences flag set the first time the sample post is
/// seeded, so deleting the sample is respected and it never re-seeds.
const samplePostSeededKey = 'byahetayo_sample_post_seeded';

/// Vehicle chips for the Create form: the 8 system categories.
List<VehicleCategory> get communityVehicleCategories =>
    VehicleCategory.values;

/// Hub name the Map tab should jump to, set by a community post's
/// "View on map" button. MapTab consumes it once, then clears it.
final communityMapJump = ValueNotifier<String?>(null);

/// Approval state of a community submission.
enum PostStatus {
  /// New submission, awaiting device-owner review.
  pending,

  /// Approved by the device owner; shown as Published.
  approved,

  /// Rejected by the device owner; hidden from the main list.
  rejected,
}

/// Parses a stored status string. Absent keys mean APPROVED (legacy
/// posts predate approval and are grandfathered in); unknown values
/// mean PENDING (safer than auto-publishing corrupt data).
PostStatus postStatusFromString(String? value) {
  switch (value) {
    case 'approved':
      return PostStatus.approved;
    case 'rejected':
      return PostStatus.rejected;
    case 'pending':
      return PostStatus.pending;
    case null:
      return PostStatus.approved;
    default:
      return PostStatus.pending;
  }
}

class CommunityPost {
  const CommunityPost({
    required this.routeName,
    required this.vehicles,
    required this.hours,
    required this.fare,
    required this.hubName,
    this.from = '',
    this.to = '',
    this.photoBase64,
    this.faresByVehicle = const {},
    this.operatorName = '',
    this.status = PostStatus.pending,
    this.id,
    this.authorUid = '',
    this.createdAt,
  });

  final String routeName;
  final List<String> vehicles;
  final String hours;

  /// Legacy single fare. New posts set this to 0 and carry their
  /// fares in [faresByVehicle]; legacy posts keep their fare here.
  final double fare;
  final String hubName;

  /// Starting location (required for posts created with the new form).
  final String from;

  /// Destination (required for posts created with the new form).
  final String to;

  /// Optional route photo, base64 JPEG bytes stored with the post.
  /// Null means no photo was attached — never a placeholder image.
  final String? photoBase64;

  /// Fare per vehicle, keyed by the stored vehicle string (category
  /// id for new posts). Empty for legacy posts, which use [fare].
  final Map<String, double> faresByVehicle;

  /// Operator name, free text (e.g. a bus/cooperative name).
  /// Empty means none was given.
  final String operatorName;

  /// Approval state. New posts are pending; legacy posts load as
  /// approved (see [postStatusFromString]).
  final PostStatus status;

  /// Firestore document id. Non-null exactly for shared posts; local
  /// posts (SharedPreferences, sample post, legacy posts) have null.
  final String? id;

  /// Firebase UID of the author. Empty for local posts, which predate
  /// sharing and have no author identity.
  final String authorUid;

  /// When the shared post was created (server timestamp). Null for
  /// local posts.
  final DateTime? createdAt;

  /// True for Firestore-backed posts, false for device-only posts.
  bool get isShared => id != null;

  /// Copy with a new approval status (used by the admin screen).
  CommunityPost copyWith({
    PostStatus? status,
    String? id,
    String? authorUid,
    DateTime? createdAt,
  }) =>
      CommunityPost(
        routeName: routeName,
        vehicles: vehicles,
        hours: hours,
        fare: fare,
        hubName: hubName,
        from: from,
        to: to,
        photoBase64: photoBase64,
        faresByVehicle: faresByVehicle,
        operatorName: operatorName,
        status: status ?? this.status,
        id: id ?? this.id,
        authorUid: authorUid ?? this.authorUid,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Card title: the route itself when From/To exist, otherwise the
  /// legacy free-text route name.
  String get displayTitle {
    if (from.trim().isNotEmpty && to.trim().isNotEmpty) {
      return '${from.trim()} → ${to.trim()}';
    }
    return routeName;
  }

  /// Fare for one vehicle: its per-vehicle fare when present,
  /// otherwise null (callers fall back to the legacy fare line).
  double? fareForVehicle(String vehicle) => faresByVehicle[vehicle];

  /// Fare lines for cards/details. Per-vehicle lines when any exist
  /// (in the post's vehicle order, then any extra keys), otherwise
  /// the single legacy line when the legacy fare is above ₱0,
  /// otherwise empty (no fare shown, never a made-up number).
  List<String> get fareLines {
    if (faresByVehicle.isNotEmpty) {
      final lines = <String>[];
      for (final vehicle in vehicles) {
        final fare = faresByVehicle[vehicle];
        if (fare != null) {
          lines.add('${vehicleLabel(vehicle)}: ₱${fare.toStringAsFixed(2)}');
        }
      }
      for (final entry in faresByVehicle.entries) {
        if (!vehicles.contains(entry.key)) {
          lines.add(
            '${vehicleLabel(entry.key)}: ₱${entry.value.toStringAsFixed(2)}',
          );
        }
      }
      return lines;
    }
    if (fare > 0) return ['Fare: ₱${fare.toStringAsFixed(2)}'];
    return [];
  }

  Map<String, dynamic> toJson() => {
        'routeName': routeName,
        'vehicles': vehicles,
        'hours': hours,
        'fare': fare,
        'hubName': hubName,
        'from': from,
        'to': to,
        if (photoBase64 != null) 'photoBase64': photoBase64,
        if (faresByVehicle.isNotEmpty)
          'faresByVehicle': faresByVehicle.map(
            (key, value) => MapEntry(key, value),
          ),
        if (operatorName.isNotEmpty) 'operatorName': operatorName,
        'status': status.name,
      };

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final vehicles = json['vehicles'];
    final photo = json['photoBase64'];
    final fares = json['faresByVehicle'];
    final faresMap = <String, double>{};
    if (fares is Map) {
      for (final entry in fares.entries) {
        if (entry.key is String && entry.value is num) {
          faresMap[entry.key as String] = (entry.value as num).toDouble();
        }
      }
    }
    final operator = json['operatorName'];
    final status = json['status'];
    return CommunityPost(
      routeName: json['routeName'] is String ? json['routeName'] as String : '',
      vehicles: vehicles is List
          ? vehicles.whereType<String>().toList()
          : const <String>[],
      hours: json['hours'] is String ? json['hours'] as String : '',
      fare: json['fare'] is num ? (json['fare'] as num).toDouble() : 0,
      hubName: json['hubName'] is String ? json['hubName'] as String : '',
      from: json['from'] is String ? json['from'] as String : '',
      to: json['to'] is String ? json['to'] as String : '',
      photoBase64: photo is String && photo.isNotEmpty ? photo : null,
      faresByVehicle: faresMap,
      operatorName: operator is String ? operator : '',
      status: postStatusFromString(status is String ? status : null),
    );
  }
}

/// Whether a post belongs in the main community list: pending and
/// approved posts show; rejected posts are admin-screen only.
bool showPostInCommunityList(CommunityPost post) =>
    post.status != PostStatus.rejected;

/// Form validation for the Create sheet. From, To, at least one
/// vehicle, and a fare above ₱0 FOR EACH selected vehicle are
/// required; hours, operator, and photo are optional. Returns the
/// error message, or null when the form is valid. Nothing is
/// defaulted: a missing/invalid field blocks the save.
String? communityFormError({
  required String from,
  required String to,
  required List<String> vehicles,
  required Map<String, String> fareTexts,
}) {
  if (from.trim().isEmpty) {
    return 'Add a starting location (From) for this route.';
  }
  if (to.trim().isEmpty) {
    return 'Add a destination (To) for this route.';
  }
  if (vehicles.isEmpty) {
    return 'Pick at least one vehicle type.';
  }
  for (final vehicle in vehicles) {
    final fare = double.tryParse((fareTexts[vehicle] ?? '').trim());
    if (fare == null || fare <= 0) {
      return 'Add a fare above ₱0 for ${vehicleLabel(vehicle)}.';
    }
  }
  return null;
}

/// Loads the local-only posts. Corrupt or foreign entries are skipped,
/// never crash the tab.
Future<List<CommunityPost>> loadCommunityPosts(
  SharedPreferences prefs,
) async {
  final raw = prefs.getString(communityPostsKey);
  if (raw == null) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CommunityPost.fromJson)
        .where(
          (p) =>
              p.routeName.trim().isNotEmpty ||
              (p.from.trim().isNotEmpty && p.to.trim().isNotEmpty),
        )
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveCommunityPosts(
  SharedPreferences prefs,
  List<CommunityPost> posts,
) {
  return prefs.setString(
    communityPostsKey,
    jsonEncode(posts.map((p) => p.toJson()).toList()),
  );
}

/// The user-provided sample submission: Operator CTransco,
/// Vigan City → Cabugao, Modern Jeepney, ₱60.00. It is seeded as a
/// PENDING submission (badged "Pending verification"), never as a
/// verified fare and never as published fact. Seeding runs at most
/// once per device: after the first seed the flag is set, so deleting
/// the sample is respected and it never comes back.
const sampleCommunityPost = CommunityPost(
  routeName: 'Vigan City → Cabugao',
  vehicles: ['modern-jeepney'],
  hours: '',
  fare: 0,
  hubName: 'Vigan City',
  from: 'Vigan City',
  to: 'Cabugao',
  faresByVehicle: {'modern-jeepney': 60},
  operatorName: 'CTransco',
  status: PostStatus.pending,
);

bool _isSamplePost(CommunityPost post) =>
    post.operatorName == 'CTransco' &&
    post.from == 'Vigan City' &&
    post.to == 'Cabugao';

/// Ensures the sample submission exists exactly once. Returns the
/// list to display (sample prepended on first seed). Persists the
/// change and the flag when seeding; otherwise returns [posts]
/// unchanged.
Future<List<CommunityPost>> ensureSampleCommunityPost(
  SharedPreferences prefs,
  List<CommunityPost> posts,
) async {
  if (prefs.getBool(samplePostSeededKey) == true) return posts;
  if (posts.any(_isSamplePost)) {
    await prefs.setBool(samplePostSeededKey, true);
    return posts;
  }
  final seeded = [sampleCommunityPost, ...posts];
  await saveCommunityPosts(prefs, seeded);
  await prefs.setBool(samplePostSeededKey, true);
  return seeded;
}
