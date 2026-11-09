// Profile setup after registration (also reused for Edit Profile).
//
// Required: full name. Optional: student info (school, program, year)
// and employment info (job title, company). The photo is picked from
// the gallery with image_picker, copied into the app documents folder
// so it survives cache clears, and its local path is stored in the
// on-device profile. Nothing here touches a backend.
import 'dart:io';
import '../top_popup.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../app_layout.dart';
import '../profile_avatar.dart';
import '../profile_photo_storage.dart';
import '../profile_repository.dart';
import 'auth_service.dart';
import 'onboarding_state.dart';
import 'student_info_fields.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.user,
    required this.store,
    this.profileRepository,
    this.photoStorage = const FirebaseProfilePhotoStorage(),
    this.initial,
    this.isEdit = false,
    required this.onSaved,
  });

  final AuthUser user;
  final ProfileStore store;

  /// Remote student-profile store. Null (the default, used by older
  /// tests) means local-only: the save path behaves exactly as
  /// before. When provided, every save also writes the remote
  /// document — see [_save].
  final StudentProfileRepository? profileRepository;

  /// Remote photo upload. Defaults to the real Firebase Storage
  /// implementation; tests pass a fake, and passing null disables
  /// uploads (local-only mode). Only used when [profileRepository]
  /// is non-null — without a remote document there is nowhere to
  /// record the download URL, so an upload would orphan the file.
  final ProfilePhotoStorage? photoStorage;

  /// Existing profile for edit mode; null for first-time setup.
  final UserProfile? initial;

  /// True when opened from Account (edit) instead of first-time setup.
  final bool isEdit;

  final ValueChanged<UserProfile> onSaved;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _schoolManualController;
  late final TextEditingController _programManualController;
  late final TextEditingController _jobController;
  late final TextEditingController _companyController;

  /// Selected listed school, or null when none / manual mode.
  String? _selectedSchool;

  /// True when the user picked the manual school option (or the saved
  /// school is not a listed school, so it must stay editable as text).
  bool _schoolManual = false;

  /// Selected listed program, or null when none / manual mode.
  ProgramOption? _selectedProgram;

  /// True when the user picked the manual program option (or the saved
  /// program is not a listed program).
  bool _programManual = false;

  /// Selected year level, or null when none.
  String? _year;

  /// Legacy free-text year that no dropdown option covers. Preserved
  /// verbatim on save until the user picks a dropdown year, so the
  /// switch to the dropdown never silently drops a saved value.
  String? _legacyYear;

  String? _photoPath;
  String? _photoUrl;

  /// Download URL of the uploaded photo (Firestore). Carried as
  /// screen state so an edit that changes nothing else never drops
  /// the URL from the remote document.
  String? _profilePhotoUrl;

  /// True when the local photo still needs uploading: the user
  /// picked a new photo in this session, or a previous upload is
  /// still pending. Cleared only after the upload AND the remote
  /// document save both succeed.
  bool _photoPending = false;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(
      text: initial?.displayName ??
          widget.user.displayName ??
          widget.user.email.split('@').first,
    );
    _emailController = TextEditingController(text: widget.user.email);
    _schoolManualController = TextEditingController();
    _programManualController = TextEditingController();
    _jobController = TextEditingController(text: initial?.jobTitle ?? '');
    _companyController =
        TextEditingController(text: initial?.company ?? '');
    _photoPath = initial?.photoPath;
    _photoUrl = initial?.photoUrl;
    _profilePhotoUrl = initial?.profilePhotoUrl;
    _photoPending = initial?.photoUploadPending ?? false;

    // Prefill student fields from the existing profile. A saved value
    // that matches a listed entry lands on the option; any other
    // non-empty saved value lands in the manual field, so editing
    // never loses what was saved before.
    final savedSchool = (initial?.school ?? '').trim();
    if (savedSchool.isNotEmpty) {
      final canonical = canonicalSchool(savedSchool);
      if (canonical != null) {
        _selectedSchool = canonical;
      } else {
        _schoolManual = true;
        _schoolManualController.text = savedSchool;
      }
    }
    final savedProgram = (initial?.program ?? '').trim();
    if (savedProgram.isNotEmpty) {
      final matched = matchProgram(savedProgram);
      if (matched != null) {
        _selectedProgram = matched;
      } else {
        _programManual = true;
        _programManualController.text = savedProgram;
      }
    }
    final savedYear = (initial?.year ?? '').trim();
    if (savedYear.isNotEmpty) {
      _year = normalizeYearLevel(savedYear);
      if (_year == null) _legacyYear = savedYear;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _schoolManualController.dispose();
    _programManualController.dispose();
    _jobController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  /// Effective school value for save: the listed selection, or the
  /// manual text (canonicalized when it duplicates a listed school).
  /// Empty means "no school set" — valid, and the store writes '' to
  /// the calendar contract key (never an "empty school entry").
  String? _effectiveSchool() {
    if (_schoolManual) {
      final manual = _schoolManualController.text.trim();
      if (manual.isEmpty) return null;
      return canonicalSchool(manual) ?? manual;
    }
    return _selectedSchool;
  }

  String? _effectiveProgram() {
    if (_programManual) {
      final manual = _programManualController.text.trim();
      if (manual.isEmpty) return null;
      final matched = matchProgram(manual);
      return matched?.display ?? manual;
    }
    return _selectedProgram?.display;
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      final docs = await getApplicationDocumentsDirectory();
      final target = File(
        '${docs.path}/byahetayo_profile_${widget.user.uid}.jpg',
      );
      await File(picked.path).copy(target.path);
      if (!mounted) return;
      setState(() {
        _photoPath = target.path;
        // A new pick always needs uploading, even when an older
        // remote URL exists (the local file is now newer than it).
        _photoPending = true;
      });
    } catch (_) {
      if (!mounted) return;
      TopPopup.show(context, message: 'Could not pick a photo.');
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var profile = UserProfile(
        displayName: name,
        email: widget.user.email,
        photoPath: _photoPath,
        photoUrl: _photoUrl,
        profilePhotoUrl: _profilePhotoUrl,
        photoUploadPending: _photoPending,
        school: _effectiveSchool(),
        program: _effectiveProgram(),
        year: _year ?? _legacyYear,
        jobTitle: _emptyToNull(_jobController.text),
        company: _emptyToNull(_companyController.text),
      );
      await widget.store.saveProfile(widget.user.uid, profile);
      // Remote save (when a repository is wired): the local save
      // above already succeeded, so a remote failure must NEVER
      // corrupt or blank local data — and must never trap the user
      // on this screen (e.g. while the Firestore rules are not yet
      // published, every remote write fails). Surface it honestly
      // via a SnackBar (shown on the root messenger, so it survives
      // the gate switch to the dashboard) and proceed: the next
      // authenticated start backfills the missing remote document
      // from the intact local data.
      final repo = widget.profileRepository;
      if (repo != null) {
        // Photo upload first, so the remote document carries the
        // fresh URL. Attempted when a local photo file exists and
        // EITHER it was picked in this session / is still pending
        // OR no remote URL is stored yet (an old local photo that
        // predates this feature — the migration case). Uploading
        // again when the URL is already stored would be pure waste.
        String? photoError;
        String? uploadedUrl;
        final photoFile = _photoPath;
        final needsUpload = (_photoPending ||
                (_profilePhotoUrl ?? '').trim().isEmpty) &&
            photoFile != null &&
            File(photoFile).existsSync() &&
            widget.photoStorage != null;
        if (needsUpload) {
          try {
            uploadedUrl = await widget.photoStorage!
                .uploadPhoto(widget.user.uid, File(photoFile));
          } catch (e) {
            photoError = profilePhotoUploadErrorMessage(e);
          }
        }
        // The profile that actually reaches the server: with the new
        // URL only when the upload succeeded. The pending flag clears
        // only after the remote document save below confirms the URL
        // — if that save fails, the local profile keeps pending=true
        // and the next sign-in retries the upload.
        var savedProfile = profile;
        if (uploadedUrl != null) {
          savedProfile = profile.copyWith(
            profilePhotoUrl: uploadedUrl,
            photoUploadPending: false,
          );
        }
        try {
          await repo.saveProfile(
            widget.user.uid,
            StudentProfile.fromUserProfile(savedProfile),
          );
          if (uploadedUrl != null) {
            // Remote confirmed: persist the URL locally too.
            await widget.store.saveProfile(widget.user.uid, savedProfile);
            profile = savedProfile;
            _profilePhotoUrl = uploadedUrl;
            _photoPending = false;
          }
        } catch (e) {
          if (mounted) {
            TopPopup.show(context, message: 'Saved on this device, but could not sync to the ' 'server (${studentProfileSyncErrorMessage(e)}). ' 'It will sync on your next sign-in.',);
          }
        }
        if (photoError != null && mounted) {
          TopPopup.show(context, message: 'Photo saved on this device, but could not upload it ' '($photoError). It will upload on your next sign-in.',);
        }
      }
      if (!widget.isEdit) {
        await widget.store.markProfileSetupDone(widget.user.uid);
      }
      if (!mounted) return;
      widget.onSaved(profile);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save your profile.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoImage = resolveProfilePhoto(
      photoPath: _photoPath,
      profilePhotoUrl: _profilePhotoUrl,
      photoUrl: _photoUrl,
    );
    final hasPhoto = photoImage != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit profile' : 'Set up your profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppLayout.pagePaddingLarge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: scheme.primary,
                    backgroundImage: photoImage,
                    child: hasPhoto
                        ? null
                        : Text(
                            _initials(_nameController.text),
                            style: AppText.displayLarge.copyWith(color: Colors.white),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Change photo'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Student information (optional)',
                style: AppText.cardTitle,
              ),
              const SizedBox(height: 12),
              SearchableDropdownField(
                label: 'School',
                displayValue: _schoolManual
                    ? (_schoolManualController.text.trim().isEmpty
                        ? null
                        : _schoolManualController.text.trim())
                    : _selectedSchool,
                options: philippineSchools,
                manualOptionLabel: manualSchoolOption,
                onSelected: (value) {
                  setState(() {
                    if (value == manualSchoolOption) {
                      _schoolManual = true;
                      _selectedSchool = null;
                    } else {
                      _schoolManual = false;
                      _selectedSchool = value;
                      _schoolManualController.clear();
                    }
                  });
                },
                onCleared: () {
                  setState(() {
                    _schoolManual = false;
                    _selectedSchool = null;
                    _schoolManualController.clear();
                  });
                },
              ),
              if (_schoolManual) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _schoolManualController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Enter university / college',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              SearchableDropdownField(
                label: 'Program / course',
                displayValue: _programManual
                    ? (_programManualController.text.trim().isEmpty
                        ? null
                        : _programManualController.text.trim())
                    : _selectedProgram?.display,
                options: philippinePrograms.map((p) => p.display).toList(),
                manualOptionLabel: manualProgramOption,
                onSelected: (value) {
                  setState(() {
                    if (value == manualProgramOption) {
                      _programManual = true;
                      _selectedProgram = null;
                    } else {
                      _programManual = false;
                      _selectedProgram = matchProgram(value);
                      _programManualController.clear();
                    }
                  });
                },
                onCleared: () {
                  setState(() {
                    _programManual = false;
                    _selectedProgram = null;
                    _programManualController.clear();
                  });
                },
              ),
              if (_programManual) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _programManualController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Enter program / course',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // A legacy free-text year shows as its own item so the
                // field never claims "Not set" while a value is saved.
                value: _year ?? _legacyYear,
                decoration: const InputDecoration(
                  labelText: 'Year level',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Not set'),
                  ),
                  ...yearLevels.map(
                    (year) => DropdownMenuItem<String?>(
                      value: year,
                      child: Text(year),
                    ),
                  ),
                  if (_legacyYear != null &&
                      !yearLevels.contains(_legacyYear))
                    DropdownMenuItem<String?>(
                      value: _legacyYear,
                      child: Text(_legacyYear!),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    if (value == null) {
                      _year = null;
                      _legacyYear = null;
                    } else if (yearLevels.contains(value)) {
                      _year = value;
                      _legacyYear = null;
                    }
                    // Re-selecting the legacy item leaves it untouched.
                  });
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Employment information (optional)',
                style: AppText.cardTitle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _jobController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Job title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _companyController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.isEdit ? 'Save changes' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}
