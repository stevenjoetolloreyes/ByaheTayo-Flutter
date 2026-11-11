// My Student ID: an ID-card view rendered ONLY from real profile
// data (name, email, school/program/year when provided). No ID numbers,
// no school, and no photo are ever invented: when no student info was
// provided (it is optional), the card shows an honest empty state that
// leads to Profile Setup.
import 'app_layout.dart';
import 'minecraft_theme.dart';
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
          padding: AppLayout.pagePaddingLarge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MinecraftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            MinecraftColors.deepLeaves,
                            MinecraftColors.grassGreen,
                          ],
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
                                    style: MinecraftText.heading(
                                      color: MinecraftColors.deepLeaves,
                                      fontSize: 24,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EstudyanteGO',
                                  style: MinecraftText.heading(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  'Student ID',
                                  style: MinecraftText.body(
                                    color: Colors.white70,
                                  ),
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
              const SizedBox(height: AppSpacing.s16),
              if (!profile.hasStudentInfo)
                MinecraftCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No student info yet',
                          style: MinecraftText.title(),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Student info is optional. Add your school, '
                          'program, and year level in Profile Setup and '
                          'they will appear on this card.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: minecraftBlockButtonStyle(),
                          onPressed: onEditProfile,
                          child: const Text('Open Profile Setup'),
                        ),
                      ],
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
          style: MinecraftText.button(fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(value, style: MinecraftText.bodySemiBold(fontSize: 16)),
      ],
    );
  }
}
