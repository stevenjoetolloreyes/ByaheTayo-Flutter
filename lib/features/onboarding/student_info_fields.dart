// Searchable dropdown fields for the Profile Setup / Edit Profile screen.
//
// The school list contains REAL Philippine universities and colleges
// only — no invented names. It is deliberately not exhaustive: anything
// not listed is covered by the "Enter University / College" manual
// option, so an incomplete list is never a functional gap.
//
// The school value always flows through the existing
// ProfileStore.saveProfile path, which syncs it to the
// `byahetayo_profile_school` contract key the School Calendar reads.
// Nothing here invents a new key or touches the store mechanism.
import 'package:flutter/material.dart';

/// Real Philippine universities and colleges (alphabetical). Includes
/// the University of Northern Philippines. No duplicates.
const philippineSchools = <String>[
  'Adamson University',
  'Angeles University Foundation',
  'Ateneo de Manila University',
  'Batangas State University',
  'Bicol University',
  'Bulacan State University',
  'Cagayan State University',
  'Cavite State University',
  'Central Luzon State University',
  'Central Mindanao University',
  'Central Philippine University',
  'De La Salle University',
  'Don Mariano Marcos Memorial State University',
  'Far Eastern University',
  'Holy Angel University',
  'Ilocos Sur Polytechnic State College',
  'Isabela State University',
  'Laguna State Polytechnic University',
  'Lorma Colleges',
  'Lyceum of the Philippines University',
  'Mapúa University',
  'Mariano Marcos State University',
  'Mindanao State University',
  'Mindoro State University',
  'National University',
  'Notre Dame of Dadiangas University',
  'Nueva Vizcaya State University',
  'Palawan State University',
  'Pangasinan State University',
  'Polytechnic University of the Philippines',
  'Saint Louis University',
  "Saint Mary's University",
  'Saint Paul University Philippines',
  'San Beda University',
  'Silliman University',
  'Tarlac State University',
  'University of Baguio',
  'University of Cebu',
  'University of La Salette',
  'University of Mindanao',
  'University of Negros Occidental – Recoletos',
  'University of Northern Philippines',
  'University of San Carlos',
  'University of San Jose–Recoletos',
  'University of Santo Tomas',
  'University of Southeastern Philippines',
  'University of the Assumption',
  'University of the East',
  'University of the Philippines',
  'West Visayas State University',
  'Xavier University – Ateneo de Cagayan',
];

/// Manual-entry option shown pinned at the bottom of the school sheet.
const manualSchoolOption = 'Enter University / College';

/// Canonical spelling of a school when [value] matches a listed school
/// case-insensitively; null otherwise. Used so a manual entry that
/// duplicates a listed school is stored under the listed spelling
/// instead of creating a second, differently-cased entry.
String? canonicalSchool(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final school in philippineSchools) {
    if (school.toLowerCase() == normalized) return school;
  }
  return null;
}

/// A Philippine college program: abbreviation + full name.
class ProgramOption {
  const ProgramOption(this.abbreviation, this.fullName);

  final String abbreviation;
  final String fullName;

  /// Display form used in the dropdown and stored in the profile, so
  /// every consumer (e.g. the Account tab) shows both forms.
  String get display => '$abbreviation – $fullName';
}

const philippinePrograms = <ProgramOption>[
  ProgramOption(
    'BSIT',
    'Bachelor of Science in Information Technology',
  ),
  ProgramOption(
    'BSCS',
    'Bachelor of Science in Computer Science',
  ),
  ProgramOption(
    'BSBA',
    'Bachelor of Science in Business Administration',
  ),
  ProgramOption(
    'BSED',
    'Bachelor of Secondary Education',
  ),
  ProgramOption(
    'BEED',
    'Bachelor of Elementary Education',
  ),
  ProgramOption(
    'BSCRIM',
    'Bachelor of Science in Criminology',
  ),
  ProgramOption(
    'BSHM',
    'Bachelor of Science in Hospitality Management',
  ),
];

/// Manual-entry option shown pinned at the bottom of the program sheet.
const manualProgramOption = 'Other / Enter manually';

/// Matches a stored program string to a listed option by display form,
/// abbreviation, or full name (case-insensitive); null when the value
/// is a manual entry. Used for prefill so legacy free-text values that
/// name a listed program land on the option instead of the manual field.
ProgramOption? matchProgram(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final program in philippinePrograms) {
    if (program.display.toLowerCase() == normalized ||
        program.abbreviation.toLowerCase() == normalized ||
        program.fullName.toLowerCase() == normalized) {
      return program;
    }
  }
  return null;
}

const yearLevels = <String>[
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
  'Graduate / Postgraduate',
];

/// Normalizes common legacy free-text year values to a [yearLevels]
/// entry; null when the value is not a recognizable year. Unrecognized
/// values are preserved verbatim by the screen (legacy passthrough) so
/// switching to the dropdown never silently drops a saved year.
String? normalizeYearLevel(String value) {
  switch (value.trim().toLowerCase()) {
    case '1st year':
    case '1st':
    case '1':
    case 'first year':
    case 'year 1':
      return '1st Year';
    case '2nd year':
    case '2nd':
    case '2':
    case 'second year':
    case 'year 2':
      return '2nd Year';
    case '3rd year':
    case '3rd':
    case '3':
    case 'third year':
    case 'year 3':
      return '3rd Year';
    case '4th year':
    case '4th':
    case '4':
    case 'fourth year':
    case 'year 4':
      return '4th Year';
    case '5th year':
    case '5th':
    case '5':
    case 'fifth year':
    case 'year 5':
      return '5th Year';
    case 'graduate':
    case 'postgraduate':
    case 'graduate / postgraduate':
    case 'grad':
    case 'masters':
    case "master's":
    case 'doctoral':
    case 'phd':
      return 'Graduate / Postgraduate';
    default:
      return null;
  }
}

/// A read-only field that opens a searchable bottom-sheet list. The
/// [manualOptionLabel], when given, stays pinned at the TOP of the
/// list regardless of the search query, so manual entry is always
/// reachable without scrolling. The sheet is scroll-controlled and
/// pads for the keyboard, so search + selection stay usable on small
/// Android phones.
class SearchableDropdownField extends StatelessWidget {
  const SearchableDropdownField({
    super.key,
    required this.label,
    required this.displayValue,
    required this.options,
    this.manualOptionLabel,
    required this.onSelected,
    this.onCleared,
  });

  final String label;

  /// Current value shown in the field; null shows the label only.
  final String? displayValue;
  final List<String> options;
  final String? manualOptionLabel;

  /// Called with the selected option, or with [manualOptionLabel] when
  /// the manual row is tapped.
  final ValueChanged<String> onSelected;
  final VoidCallback? onCleared;

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = normalizedQuery.isEmpty
                ? options
                : options
                    .where(
                      (option) =>
                          option.toLowerCase().contains(normalizedQuery),
                    )
                    .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        key: const Key('dropdown-search'),
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (manualOptionLabel != null) ...[
                            ListTile(
                              title: Text(manualOptionLabel!),
                              leading: const Icon(Icons.edit_outlined),
                              onTap: () =>
                                  Navigator.pop(context, manualOptionLabel),
                            ),
                            const Divider(height: 1),
                          ],
                          ...filtered.map(
                            (option) => ListTile(
                              title: Text(option),
                              onTap: () => Navigator.pop(context, option),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue =
        displayValue != null && displayValue!.trim().isNotEmpty;
    return TextField(
      readOnly: true,
      controller: TextEditingController(text: hasValue ? displayValue : ''),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: hasValue && onCleared != null
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear',
                onPressed: onCleared,
              )
            : const Icon(Icons.arrow_drop_down),
      ),
      onTap: () => _openSheet(context),
    );
  }
}
