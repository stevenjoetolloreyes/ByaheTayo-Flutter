// Communities tab — local-only community posts, moved out of the
// Friends tab (user's call: Communities is its own nav destination).
//
// HONEST STATE: there is no community backend — posts, fare
// complaints, and LGU directory entries are all saved on this device
// only (SharedPreferences) and never shared. No invented posts, no
// votes, no comments. Approval is admin-only (see admin_access.dart):
// new posts start Pending ("Pending verification" badge) and only
// approved posts are Published; the Post approvals screen and the LGU
// directory editor are shown only to allowlisted admin accounts — no
// server review is implied anywhere.
//
// Contains the whole Community section: the Share-info entry + Share a
// Local Route form, the local posts list with cards (From → To,
// vehicle, fare, photo, View Route details, View on map jump, Report
// Overpriced Fare flow), the saved-complaints list, and the LGU
// directory admin entry.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_access.dart';
import 'community_admin.dart';
import 'community_posts.dart';
import 'fares_tab.dart';
import 'onboarding/auth_service.dart';
import 'vehicle_categories.dart';
import 'lgu_complaint_ui.dart';
import 'lgu_complaints.dart';

class CommunitiesTab extends StatefulWidget {
  const CommunitiesTab({super.key, this.onViewOnMap, this.currentUser});

  /// Called when a community post's "View on map" is tapped, so the
  /// shell can switch to the Map tab (the jump itself travels through
  /// the communityMapJump notifier, which MapTab consumes).
  final VoidCallback? onViewOnMap;

  /// The authenticated Firebase user, if any. Admin-only actions
  /// (Post approvals, LGU directory editing) are shown only when this
  /// user is on the admin allowlist (see admin_access.dart). Null
  /// (signed out or Firebase not configured) means regular user.
  final AuthUser? currentUser;

  @override
  State<CommunitiesTab> createState() => _CommunitiesTabState();
}

class _CommunitiesTabState extends State<CommunitiesTab> {
  List<CommunityPost> _posts = [];

  /// Locally saved fare complaints (on-device only, never sent by the
  /// app). Shown once at least one exists.
  List<FareComplaint> _complaints = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadComplaints();
  }

  Future<void> _loadPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = await loadCommunityPosts(prefs);
      final posts = await ensureSampleCommunityPost(prefs, loaded);
      if (mounted) setState(() => _posts = posts);
    } catch (_) {
      // Local posts are a bonus; a failed load leaves the empty state.
    }
  }

  Future<void> _savePosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await saveCommunityPosts(prefs, _posts);
    } catch (_) {
      // The in-memory list still shows the post for this session.
    }
  }

  Future<void> _loadComplaints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final complaints = await loadFareComplaints(prefs);
      if (mounted) setState(() => _complaints = complaints);
    } catch (_) {
      // Complaint copies are a bonus; a failed load leaves them hidden.
    }
  }

  Future<void> _saveComplaints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await saveFareComplaints(prefs, _complaints);
    } catch (_) {
      // The in-memory list still shows the complaint for this session.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Local routes shared by commuters',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        const Text(
          'Communities',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        _shareInfoCard(scheme),
        const SizedBox(height: 12),
        _communitySection(),
        const SizedBox(height: 16),
        Text(
          'Community posts you create are saved on this device only — they are not shared with other users.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Reference-style "Share info" card. It opens the local-only
  /// Create form: the button does something real (saves a post on this
  /// device) instead of reporting no backend.
  Widget _shareInfoCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.edit_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Know something that can help commuters?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share local transport coverage or terminal details so other commuters can plan with better context.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _openCreateSheet,
              child: const Text('Share info'),
            ),
          ],
        ),
      ),
    );
  }

  /// Community section: local-only posts, or the honest empty state
  /// when none exist yet. No invented posts, no badges, no counts.
  Widget _communitySection() {
    final scheme = Theme.of(context).colorScheme;
    final visiblePosts =
        _posts.where(showPostInCommunityList).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Community',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Local posts only — saved on this device, not shared.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (visiblePosts.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('No announcements or posts yet.'),
              const SizedBox(height: 4),
              Text(
                'There is no community feed yet — no posts are shown, and none are invented here.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: 12),
              for (final post in visiblePosts) ...[
                _postCard(post, scheme),
                const SizedBox(height: 8),
              ],
            ],
            if (_complaints.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'My fare complaints',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Copies saved on this device only — never sent by the app.',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final complaint in _complaints) ...[
                _complaintCard(complaint, scheme),
                const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 8),
            // Admin-only actions: Post approvals and the LGU directory
            // editor are shown only to allowlisted admin accounts
            // (admin_access.dart). Regular users never see them, so
            // there is no dead button and no way to reach the editor
            // without an admin sign-in.
            if (isAdminUser(widget.currentUser))
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CommunityAdminScreen(
                            posts: _posts,
                            onChanged: (updated) {
                              setState(() => _posts = updated);
                              _savePosts();
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Post approvals'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LguAdminScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('LGU directory'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// One local post: From → To, hub, vehicles, fare, hours, photo —
  /// plus "View Route" (details view of the post), the real
  /// "View on map" jump, and "Report Overpriced Fare". No votes, no
  /// comments, no review badges.
  Widget _postCard(CommunityPost post, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.photoBase64 != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(post.photoBase64!),
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  post.displayTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: const Text('Local post'),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Chip(
            label: Text(
              post.status == PostStatus.approved
                  ? 'Published'
                  : 'Pending verification',
            ),
            backgroundColor: post.status == PostStatus.approved
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEF9C3),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 4),
          Text(post.hubName),
          if (post.vehicles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final vehicle in post.vehicles)
                  Chip(
                    avatar: Icon(vehicleIcon(vehicle), size: 18),
                    label: Text(vehicleLabel(vehicle)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (post.fareLines.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final line in post.fareLines) Text(line),
          ],
          if (post.operatorName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Operator: ${post.operatorName}'),
          ],
          if (post.hours.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Hours: ${post.hours}'),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openDetailsSheet(post),
                  child: const Text('View Route'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    communityMapJump.value = post.hubName;
                    widget.onViewOnMap?.call();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View on map'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openReportSheet(post),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report Overpriced Fare'),
            ),
          ),
        ],
      ),
    );
  }

  /// One saved complaint: reference, route, status. Tapping opens the
  /// detail sheet (message, copy, open page, mark as sent). No
  /// complainant info is ever shown on a community card.
  Widget _complaintCard(FareComplaint complaint, ColorScheme scheme) {
    final submitted = complaint.status == ComplaintStatus.submitted;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(complaint.reference),
        subtitle: Text('${complaint.from} → ${complaint.to}'),
        trailing: Chip(
          label: Text(submitted ? 'Submitted' : 'Prepared'),
          backgroundColor: submitted
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFFEF9C3),
          visualDensity: VisualDensity.compact,
        ),
        onTap: () => _openComplaintDetail(complaint),
      ),
    );
  }

  /// Details view of one post: full info + photo when present.
  /// Deliberately NOT a Map jump: the Map tab routes between hubs,
  /// and free-text From/To towns cannot map to hubs reliably.
  Future<void> _openDetailsSheet(CommunityPost post) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.displayTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Local post — saved on this device, not shared.',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (post.photoBase64 != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(post.photoBase64!),
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (post.from.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.trip_origin_outlined),
                  title: const Text('From'),
                  subtitle: Text(post.from),
                ),
              if (post.to.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('To'),
                  subtitle: Text(post.to),
                ),
              if (post.vehicles.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.directions_bus_outlined),
                  title: const Text('Vehicles'),
                  subtitle: Text(
                    post.vehicles.map(vehicleLabel).join(', '),
                  ),
                ),
              if (post.fareLines.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Fare'),
                  subtitle: Text(post.fareLines.join('\n')),
                ),
              if (post.operatorName.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('Operator'),
                  subtitle: Text(post.operatorName),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Status'),
                subtitle: Text(
                  post.status == PostStatus.approved
                      ? 'Published'
                      : 'Pending verification',
                ),
              ),
              if (post.hours.trim().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Operating hours'),
                  subtitle: Text(post.hours),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Location'),
                subtitle: Text(post.hubName),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Report flow: pre-filled form -> save locally (Prepared) ->
  /// detail sheet with the message, copy, and open-page actions.
  /// Opening Facebook never marks the complaint Submitted; only the
  /// confirm dialog inside the detail sheet does.
  Future<void> _openReportSheet(CommunityPost post) async {
    final complaint = await showModalBottomSheet<FareComplaint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportFareSheet(
        post: post,
        existingReferences:
            _complaints.map((c) => c.reference).toList(),
      ),
    );
    if (complaint == null || !mounted) return;
    setState(() => _complaints = [..._complaints, complaint]);
    await _saveComplaints();
    if (!mounted) return;
    await _openComplaintDetail(complaint);
  }

  /// Complaint detail sheet; pops with the current complaint (possibly
  /// status-updated) or null when dismissed by drag.
  Future<void> _openComplaintDetail(FareComplaint complaint) async {
    final updated = await showModalBottomSheet<FareComplaint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ComplaintDetailSheet(complaint: complaint),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _complaints = _complaints
          .map((c) => c.reference == updated.reference ? updated : c)
          .toList();
    });
    await _saveComplaints();
  }

  /// Create sheet (reference Local Transport form, updated): From +
  /// To + vehicle + fare required, hours + photo optional, location
  /// = one of ByaheTayo's own 14 hubs. Saves locally only.
  Future<void> _openCreateSheet() async {
    final post = await showModalBottomSheet<CommunityPost>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreatePostSheet(),
    );
    if (post == null || !mounted) return;
    setState(() => _posts = [..._posts, post]);
    await _savePosts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Post saved locally — pending verification.'),
      ),
    );
  }
}

/// Create-post sheet content. Owns its controllers so they are disposed
/// with the sheet itself (after its exit transition), never while the
/// sheet's fields are still built. Pops with the finished post, or null
/// when dismissed.
class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet();

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _hoursController = TextEditingController();
  final _operatorController = TextEditingController();

  /// One fare controller per selected vehicle id. Controllers are
  /// created when a chip is selected and disposed with the sheet;
  /// deselecting keeps the controller (and its text) so reselecting
  /// restores the fare.
  final _fareControllers = <String, TextEditingController>{};
  final _selectedVehicles = <String>{};

  /// Optional attached photo, base64 JPEG bytes (capped by the picker
  /// to 1200px wide, quality 80, so the stored string stays modest).
  /// Null means no photo — never a placeholder image.
  String? _photoBase64;
  late String _selectedHub =
      hubs.any((h) => h.name == 'Cabugao') ? 'Cabugao' : hubs.first.name;
  var _error = '';

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _hoursController.dispose();
    _operatorController.dispose();
    for (final controller in _fareControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Gallery pick only (no camera permission needed). A failed pick
  /// shows an inline error and leaves the form untouched.
  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBase64 = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not attach that photo. Try another one.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share a local route',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Saved on this device only — not shared.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fromController,
              decoration: const InputDecoration(
                labelText: 'From *',
                hintText: 'e.g. Cabugao',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _toController,
              decoration: const InputDecoration(
                labelText: 'To *',
                hintText: 'e.g. Vigan City',
              ),
            ),
            const SizedBox(height: 12),
            const Text('Vehicle *'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final category in communityVehicleCategories)
                  FilterChip(
                    avatar: Icon(category.icon, size: 18),
                    label: Text(category.label),
                    selected: _selectedVehicles.contains(category.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selectedVehicles.add(category.id);
                        _fareControllers.putIfAbsent(
                          category.id,
                          TextEditingController.new,
                        );
                      } else {
                        _selectedVehicles.remove(category.id);
                      }
                    }),
                  ),
              ],
            ),
            for (final vehicle in _selectedVehicles) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _fareControllers.putIfAbsent(
                  vehicle,
                  TextEditingController.new,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Fare for ${vehicleLabel(vehicle)} (₱) *',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _hoursController,
              decoration: const InputDecoration(
                labelText: 'Operating hours (optional)',
                hintText: 'e.g. 6:00 AM – 9:00 PM',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _operatorController,
              decoration: const InputDecoration(
                labelText: 'Operator (optional)',
                hintText: 'e.g. bus or cooperative name',
              ),
            ),
            const SizedBox(height: 12),
            if (_photoBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(_photoBase64!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _photoBase64 = null),
                icon: const Icon(Icons.delete_outlined),
                label: const Text('Remove photo'),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Add photo (optional)'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedHub,
              decoration: const InputDecoration(labelText: 'Location'),
              items: [
                for (final hub in hubs)
                  DropdownMenuItem(value: hub.name, child: Text(hub.name)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _selectedHub = v);
              },
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('Save post'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final formError = communityFormError(
      from: _fromController.text,
      to: _toController.text,
      vehicles: _selectedVehicles.toList(),
      fareTexts: {
        for (final vehicle in _selectedVehicles)
          vehicle: _fareControllers[vehicle]?.text ?? '',
      },
    );
    if (formError != null) {
      setState(() => _error = formError);
      return;
    }
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    Navigator.of(context).pop(
      CommunityPost(
        routeName: '$from → $to',
        from: from,
        to: to,
        vehicles: _selectedVehicles.toList(),
        hours: _hoursController.text.trim(),
        // The legacy single fare stays 0: the per-vehicle fares below
        // are authoritative for new posts.
        fare: 0,
        hubName: _selectedHub,
        photoBase64: _photoBase64,
        faresByVehicle: {
          for (final vehicle in _selectedVehicles)
            vehicle: double.parse(
              _fareControllers[vehicle]!.text.trim(),
            ),
        },
        operatorName: _operatorController.text.trim(),
      ),
    );
  }
}
