// LGU fare-complaint directory + local complaint copies.
//
// HONEST SHAPE: the app cannot file a complaint with an LGU itself —
// it has no LGU integration. What it CAN do: keep a local directory of
// LGU Facebook pages, draft a formatted complaint message, save a copy
// on this device, and open the LGU's official page so the user can send
// the message themselves. Status is NEVER auto-marked Submitted: opening
// Facebook proves nothing, so only the user's explicit "Did you send
// it? Yes" marks a complaint Submitted, with a timestamp.
//
// NEVER invent a Facebook URL: the seed below contains ONLY pages
// verified against official sources (see sourceNote). Municipalities
// without a confirmed official page are left OUT — the report flow
// shows an honest empty state for them instead of a fake link. New
// entries come from the in-app LGU admin screen, stored locally.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'fares_tab.dart';

/// SharedPreferences key for the local LGU directory.
const lguDirectoryKey = 'byahetayo_lgu_directory';

/// SharedPreferences key for the local complaint copies.
const fareComplaintsKey = 'byahetayo_fare_complaints';

/// One LGU directory entry. [facebookUrl] is empty when no official
/// page is known; [verified] means the page was confirmed as the
/// municipality/city government's official page (see [sourceNote]).
class LguEntry {
  const LguEntry({
    required this.id,
    required this.municipality,
    required this.lguName,
    this.facebookUrl = '',
    this.contactInfo = '',
    this.verified = false,
    this.sourceNote = '',
  });

  final String id;
  final String municipality;
  final String lguName;
  final String facebookUrl;
  final String contactInfo;
  final bool verified;
  final String sourceNote;

  /// True only when the entry may be opened as the official page.
  bool get hasVerifiedPage =>
      verified && facebookUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'municipality': municipality,
        'lguName': lguName,
        'facebookUrl': facebookUrl,
        'contactInfo': contactInfo,
        'verified': verified,
        'sourceNote': sourceNote,
      };

  factory LguEntry.fromJson(Map<String, dynamic> json) {
    final municipality =
        json['municipality'] is String ? json['municipality'] as String : '';
    final id = json['id'] is String && (json['id'] as String).isNotEmpty
        ? json['id'] as String
        : municipality.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return LguEntry(
      id: id,
      municipality: municipality,
      lguName: json['lguName'] is String ? json['lguName'] as String : '',
      facebookUrl:
          json['facebookUrl'] is String ? json['facebookUrl'] as String : '',
      contactInfo:
          json['contactInfo'] is String ? json['contactInfo'] as String : '',
      verified: json['verified'] is bool ? json['verified'] as bool : false,
      sourceNote:
          json['sourceNote'] is String ? json['sourceNote'] as String : '',
    );
  }
}

/// Seed directory: ONLY pages verified against official sources.
/// Vigan City PH — confirmed by The Vigan Chronicle (the City
/// Government of Vigan's own official publication) listing
/// "f /ViganCityPH", and by PIA naming "Vigan City PH" as the official
/// channel for transport concerns. Cabugao is deliberately NOT here:
/// no official municipal page could be confirmed (the only Facebook
/// link found was a PESO employment-office page, and the DTI-CMCI
/// profile's Facebook field is empty).
const seedLguEntries = [
  LguEntry(
    id: 'vigan-city',
    municipality: 'Vigan City',
    lguName: 'City Government of Vigan',
    facebookUrl: 'https://www.facebook.com/ViganCityPH',
    contactInfo:
        'admin@vigancity.gov.ph · (077) 722-8771–75 · Vigan City Hall, Brgy I, Burgos St. cor. Quezon Ave.',
    verified: true,
    sourceNote:
        'Verified via The Vigan Chronicle (official publication of the City Government of Vigan) and PIA.',
  ),
];

/// Finds the directory entry for one municipality — the post's
/// Location (hub) value, NOT free-text From/To: a route spans two
/// towns, so silently picking the destination's LGU would misdirect
/// the complaint. Case-insensitive; null when nothing matches, and
/// the caller shows the honest empty state.
LguEntry? findLguForMunicipality(
  List<LguEntry> entries,
  String municipality,
) {
  final want = municipality.trim().toLowerCase();
  if (want.isEmpty) return null;
  for (final entry in entries) {
    if (entry.municipality.trim().toLowerCase() == want) return entry;
  }
  return null;
}

Future<List<LguEntry>> loadLguEntries(SharedPreferences prefs) async {
  final raw = prefs.getString(lguDirectoryKey);
  if (raw == null) return [...seedLguEntries];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [...seedLguEntries];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LguEntry.fromJson)
        .where((e) => e.municipality.trim().isNotEmpty)
        .toList();
  } catch (_) {
    return [...seedLguEntries];
  }
}

Future<void> saveLguEntries(
  SharedPreferences prefs,
  List<LguEntry> entries,
) {
  return prefs.setString(
    lguDirectoryKey,
    jsonEncode(entries.map((e) => e.toJson()).toList()),
  );
}

/// Validation for an LGU directory entry. Municipality + LGU name are
/// required; a URL, when given, must be http(s); verified requires a
/// URL (verified means the official page, not just the LGU).
String? lguEntryError({
  required String municipality,
  required String lguName,
  required String facebookUrl,
  required bool verified,
}) {
  if (municipality.trim().isEmpty) {
    return 'Add the municipality or city name.';
  }
  if (lguName.trim().isEmpty) {
    return 'Add the official LGU name.';
  }
  final url = facebookUrl.trim();
  if (url.isNotEmpty &&
      !url.startsWith('http://') &&
      !url.startsWith('https://')) {
    return 'The Facebook Page URL must start with https://.';
  }
  if (verified && url.isEmpty) {
    return 'A verified entry needs its official Facebook Page URL.';
  }
  return null;
}

enum ComplaintStatus { prepared, submitted }

/// One locally saved fare complaint. The app never sends it anywhere:
/// [status] starts Prepared and becomes Submitted ONLY through the
/// user's explicit confirmation (see [markComplaintSent]).
class FareComplaint {
  const FareComplaint({
    required this.reference,
    required this.from,
    required this.to,
    required this.vehicle,
    required this.reportedFare,
    this.expectedFare,
    required this.dateTime,
    required this.location,
    required this.description,
    this.photoBase64,
    this.complainantName = '',
    this.complainantContact = '',
    this.includePersonalInfo = false,
    this.status = ComplaintStatus.prepared,
    this.submittedAt,
  });

  final String reference;
  final String from;
  final String to;
  final String vehicle;
  final double reportedFare;
  final double? expectedFare;
  final DateTime dateTime;
  final String location;
  final String description;

  /// Optional photo evidence, base64 JPEG bytes (same approach as the
  /// route-post photo). Null means no evidence attached.
  final String? photoBase64;

  /// Complainant info, included in the message ONLY when
  /// [includePersonalInfo] is true. Never shown on community cards.
  final String complainantName;
  final String complainantContact;
  final bool includePersonalInfo;
  final ComplaintStatus status;

  /// When the user confirmed sending. Null while Prepared.
  final DateTime? submittedAt;

  FareComplaint copyWith({
    ComplaintStatus? status,
    DateTime? submittedAt,
  }) {
    return FareComplaint(
      reference: reference,
      from: from,
      to: to,
      vehicle: vehicle,
      reportedFare: reportedFare,
      expectedFare: expectedFare,
      dateTime: dateTime,
      location: location,
      description: description,
      photoBase64: photoBase64,
      complainantName: complainantName,
      complainantContact: complainantContact,
      includePersonalInfo: includePersonalInfo,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'from': from,
        'to': to,
        'vehicle': vehicle,
        'reportedFare': reportedFare,
        if (expectedFare != null) 'expectedFare': expectedFare,
        'dateTime': dateTime.toIso8601String(),
        'location': location,
        'description': description,
        if (photoBase64 != null) 'photoBase64': photoBase64,
        'complainantName': complainantName,
        'complainantContact': complainantContact,
        'includePersonalInfo': includePersonalInfo,
        'status': status.name,
        if (submittedAt != null)
          'submittedAt': submittedAt!.toIso8601String(),
      };

  factory FareComplaint.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value, DateTime fallback) {
      if (value is String) {
        return DateTime.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    final expected = json['expectedFare'];
    final photo = json['photoBase64'];
    final statusRaw = json['status'];
    return FareComplaint(
      reference:
          json['reference'] is String ? json['reference'] as String : '',
      from: json['from'] is String ? json['from'] as String : '',
      to: json['to'] is String ? json['to'] as String : '',
      vehicle: json['vehicle'] is String ? json['vehicle'] as String : '',
      reportedFare: json['reportedFare'] is num
          ? (json['reportedFare'] as num).toDouble()
          : 0,
      expectedFare: expected is num ? expected.toDouble() : null,
      dateTime: parseDate(json['dateTime'], DateTime.now()),
      location:
          json['location'] is String ? json['location'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
      photoBase64: photo is String && photo.isNotEmpty ? photo : null,
      complainantName: json['complainantName'] is String
          ? json['complainantName'] as String
          : '',
      complainantContact: json['complainantContact'] is String
          ? json['complainantContact'] as String
          : '',
      includePersonalInfo: json['includePersonalInfo'] is bool
          ? json['includePersonalInfo'] as bool
          : false,
      status: statusRaw == 'submitted'
          ? ComplaintStatus.submitted
          : ComplaintStatus.prepared,
      submittedAt: json['submittedAt'] is String
          ? DateTime.tryParse(json['submittedAt'] as String)
          : null,
    );
  }
}

/// Unique local reference: BT-YYYYMMDD-NNNN, sequenced per day against
/// [existingReferences] so two complaints on one day never collide.
/// Pure (unit-tested).
String generateComplaintReference(
  DateTime now,
  List<String> existingReferences,
) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final prefix =
      'BT-${now.year}${pad(now.month)}${pad(now.day)}-';
  var maxSeq = 0;
  for (final ref in existingReferences) {
    if (!ref.startsWith(prefix)) continue;
    final seq = int.tryParse(ref.substring(prefix.length));
    if (seq != null && seq > maxSeq) maxSeq = seq;
  }
  return '$prefix${(maxSeq + 1).toString().padLeft(4, '0')}';
}

/// 'yyyy-MM-dd HH:mm' without a date-format dependency.
String formatComplaintDateTime(DateTime dt) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
      '${pad(dt.hour)}:${pad(dt.minute)}';
}

/// The message the user copies and sends themselves. Personal info
/// appears ONLY when the user consented; a photo is never embedded —
/// the note tells the user to attach it manually.
String formatComplaintMessage(FareComplaint c, {LguEntry? lgu}) {
  final lines = <String>[
    'Overpriced Fare Complaint — ${c.reference}',
    'Route: ${c.from} → ${c.to}',
    'Vehicle: ${c.vehicle}',
    'Reported fare: ${peso(c.reportedFare)}',
    if (c.expectedFare != null) 'Expected fare: ${peso(c.expectedFare!)}',
    'Date & time: ${formatComplaintDateTime(c.dateTime)}',
    'Location: ${c.location}',
    'Description: ${c.description}',
  ];
  if (c.includePersonalInfo) {
    final who = [
      c.complainantName.trim(),
      c.complainantContact.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    if (who.isNotEmpty) lines.add('Reported by: $who');
  }
  if (c.photoBase64 != null) {
    lines.add(
      'Note: Photo evidence is saved on-device; please attach it to your message.',
    );
  }
  if (lgu != null) {
    lines.add('LGU: ${lgu.lguName} (${lgu.municipality})');
  }
  return lines.join('\n');
}

/// The ONLY status transition: the user's explicit confirmation that
/// they sent the message. Opening Facebook never calls this.
FareComplaint markComplaintSent(FareComplaint c, DateTime now) {
  if (c.status == ComplaintStatus.submitted) return c;
  return c.copyWith(status: ComplaintStatus.submitted, submittedAt: now);
}

/// Report-form validation. From, To, vehicle, reported fare above ₱0,
/// and a description are required; expected fare, when given, must
/// also be above ₱0. Nothing is defaulted.
String? complaintFormError({
  required String from,
  required String to,
  required String vehicle,
  required String reportedFareText,
  required String description,
  String expectedFareText = '',
}) {
  if (from.trim().isEmpty) return 'Add a starting location (From).';
  if (to.trim().isEmpty) return 'Add a destination (To).';
  if (vehicle.trim().isEmpty) return 'Add the vehicle type.';
  final fare = double.tryParse(reportedFareText.trim());
  if (fare == null || fare <= 0) {
    return 'Add a reported fare above ₱0.';
  }
  if (expectedFareText.trim().isNotEmpty) {
    final expected = double.tryParse(expectedFareText.trim());
    if (expected == null || expected <= 0) {
      return 'Expected fare must be above ₱0 when given.';
    }
  }
  if (description.trim().isEmpty) return 'Describe what happened.';
  return null;
}

Future<List<FareComplaint>> loadFareComplaints(
  SharedPreferences prefs,
) async {
  final raw = prefs.getString(fareComplaintsKey);
  if (raw == null) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FareComplaint.fromJson)
        .where((c) => c.reference.trim().isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveFareComplaints(
  SharedPreferences prefs,
  List<FareComplaint> complaints,
) {
  return prefs.setString(
    fareComplaintsKey,
    jsonEncode(complaints.map((c) => c.toJson()).toList()),
  );
}
