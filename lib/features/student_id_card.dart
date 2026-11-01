// My Student ID: an ID-card view rendered ONLY from real profile
// data (name, email, school/program/year when provided). No ID numbers,
// no school, and no photo are ever invented: when no student info was
// provided (it is optional), the card shows an honest empty state that
// leads to Profile Setup.
import 'dart:io';

import 'package:flutter/material.dart';

import 'onboarding/onboarding_state.dart';

class StudentIdCardScreen extends StatelessWidget {
  const StudentIdCardScreen({
    super.key,
    required this.profile,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final photo = profile.photoPath;
    return Scaffold(
      appBar: AppBar(title: const Text('My Student ID')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF14532D), Color(0xFF16A34A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.white,
                            backgroundImage: photo != null
                                ? FileImage(File(photo))
                                : null,
                            child: photo == null
                                ? Text(
                                    profile.initials,
                                    style: const TextStyle(
                                      color: Color(0xFF14532D),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EstudyanteGO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Student ID',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.school_outlined,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _idRow('Name', profile.displayName),
                          const SizedBox(height: 12),
                          _idRow('Email', profile.email),
                          if (profile.hasStudentInfo) ...[
                            const SizedBox(height: 12),
                            if ((profile.school ?? '').isNotEmpty)
                              _idRow('School', profile.school!),
                            if ((profile.school ?? '').isNotEmpty &&
                                ((profile.program ?? '').isNotEmpty ||
                                    (profile.year ?? '').isNotEmpty))
                              const SizedBox(height: 12),
                            if ((profile.program ?? '').isNotEmpty)
                              _idRow('Program', profile.program!),
                            if ((profile.program ?? '').isNotEmpty &&
                                (profile.year ?? '').isNotEmpty)
                              const SizedBox(height: 12),
                            if ((profile.year ?? '').isNotEmpty)
                              _idRow('Year level', profile.year!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!profile.hasStudentInfo)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No student info yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Student info is optional. Add your school, '
                          'program, and year level in Profile Setup and '
                          'they will appear on this card.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: onEditProfile,
                          child: const Text('Open Profile Setup'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'This card is rendered from your profile only. No ID '
                'number is shown because EstudyanteGO does not issue '
                'student ID numbers.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _idRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
