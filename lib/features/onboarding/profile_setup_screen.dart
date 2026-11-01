// Profile setup after registration (also reused for Edit Profile).
//
// Required: full name. Optional: student info (school, program, year)
// and employment info (job title, company). The photo is picked from
// the gallery with image_picker, copied into the app documents folder
// so it survives cache clears, and its local path is stored in the
// on-device profile. Nothing here touches a backend.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'auth_service.dart';
import 'onboarding_state.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.user,
    required this.store,
    this.initial,
    this.isEdit = false,
    required this.onSaved,
  });

  final AuthUser user;
  final ProfileStore store;

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
  late final TextEditingController _schoolController;
  late final TextEditingController _programController;
  late final TextEditingController _yearController;
  late final TextEditingController _jobController;
  late final TextEditingController _companyController;
  String? _photoPath;
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
    _schoolController = TextEditingController(text: initial?.school ?? '');
    _programController =
        TextEditingController(text: initial?.program ?? '');
    _yearController = TextEditingController(text: initial?.year ?? '');
    _jobController = TextEditingController(text: initial?.jobTitle ?? '');
    _companyController =
        TextEditingController(text: initial?.company ?? '');
    _photoPath = initial?.photoPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _schoolController.dispose();
    _programController.dispose();
    _yearController.dispose();
    _jobController.dispose();
    _companyController.dispose();
    super.dispose();
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
      setState(() => _photoPath = target.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick a photo.')),
      );
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
      final profile = UserProfile(
        displayName: name,
        email: widget.user.email,
        photoPath: _photoPath,
        school: _emptyToNull(_schoolController.text),
        program: _emptyToNull(_programController.text),
        year: _emptyToNull(_yearController.text),
        jobTitle: _emptyToNull(_jobController.text),
        company: _emptyToNull(_companyController.text),
      );
      await widget.store.saveProfile(widget.user.uid, profile);
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
    final photo = _photoPath;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit profile' : 'Set up your profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: scheme.primary,
                    backgroundImage:
                        photo != null ? FileImage(File(photo)) : null,
                    child: photo == null
                        ? Text(
                            _initials(_nameController.text),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schoolController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'School',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _programController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Program / course',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _yearController,
                decoration: const InputDecoration(
                  labelText: 'Year level',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Employment information (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                  padding: const EdgeInsets.only(top: 8),
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
