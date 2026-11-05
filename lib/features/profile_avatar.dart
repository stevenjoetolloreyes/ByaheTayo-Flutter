// Shared profile-photo resolution for the Account tab, the Student
// Hub welcome card, and the profile setup screen — ONE rule, so the
// screens can never disagree about which photo to show.
//
// Display priority:
//   1. Local file ([UserProfile.photoPath], when the file still
//      exists on disk) — the photo the user picked on this install.
//   2. Uploaded photo ([UserProfile.profilePhotoUrl] — the Firebase
//      Storage download URL saved in Firestore; survives reinstall).
//   3. Google avatar ([UserProfile.photoUrl] — set by Google
//      sign-up, only when the user never picked a custom photo).
//   4. Nothing — callers fall back to honest initials / a person
//      icon. Never a fake photo.
import 'dart:io';

import 'package:flutter/material.dart';

import 'onboarding/onboarding_state.dart';

/// The image to show for [profile], or null when no photo exists
/// (callers fall back to initials / a person icon).
ImageProvider<Object>? resolveProfilePhotoImage(UserProfile? profile) {
  return resolveProfilePhoto(
    photoPath: profile?.photoPath,
    profilePhotoUrl: profile?.profilePhotoUrl,
    photoUrl: profile?.photoUrl,
  );
}

/// Same priority as [resolveProfilePhotoImage], for call sites that
/// hold the three values as separate state (e.g. the profile setup
/// screen while the user is editing, before anything is saved).
ImageProvider<Object>? resolveProfilePhoto({
  String? photoPath,
  String? profilePhotoUrl,
  String? photoUrl,
}) {
  if (photoPath != null && File(photoPath).existsSync()) {
    return FileImage(File(photoPath));
  }
  final remote = (profilePhotoUrl ?? '').trim();
  if (remote.isNotEmpty) return NetworkImage(remote);
  final google = (photoUrl ?? '').trim();
  if (google.isNotEmpty) return NetworkImage(google);
  return null;
}
