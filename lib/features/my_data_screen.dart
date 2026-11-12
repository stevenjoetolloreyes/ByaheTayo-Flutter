// My Data screen — export + delete account (Account → Privacy →
// My Data).
//
// Shown INSIDE the Account tab (the shell's bottom navigation /
// sidebar stays visible) and returned to via [onBack], the same
// pattern as the About screen. Three views, matching the approved
// preview v1 (Nov 11, 2026):
//   1. My Data — what the app holds, grouped, with REAL counts and
//      a Download button per group.
//   2. Export — pick groups, JSON format, "Request export".
//   3. Delete — warning, "Type DELETE to confirm", final confirm,
//      re-authentication, then the real deletion.
//
// DEVIATIONS FROM THE PREVIEW (all honest, all deliberate):
// * Counts are real (the preview's were SAMPLE). There is no
//   SAMPLE tag anywhere on this screen.
// * The export is assembled ON-DEVICE and the share sheet opens
//   immediately — there is no export backend and no "we'll notify
//   you when it's ready". The success line says the export is
//   ready and to pick where to save or share it.
// * The delete list adds one honest line the preview did not have:
//   the points/credits ledgers are append-only and cannot be
//   erased by the app (the deletion report lists them as kept).
// * Chat Support messages are named in the delete list (as in the
//   preview) but the real app stores none yet — Chat Support is
//   still preview-only. When it ships, its collection belongs in
//   the deletion plan (see my_data_service.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'minecraft_theme.dart';
import 'my_data_service.dart';
import 'onboarding/auth_service.dart';
import 'onboarding/onboarding_state.dart';
import 'points_wallet_repository.dart';

enum _MyDataView { overview, export, delete }

enum _DeleteStep { warning, confirm, reauth, deleting, done }

/// Per-group display metadata (preview v1 order).
const _groupMeta = <MyDataGroup, ({String title, IconData icon, Color color})>{
  MyDataGroup.profile: (
    title: 'Profile',
    icon: Icons.person,
    color: MinecraftColors.skyBlue,
  ),
  MyDataGroup.schedule: (
    title: 'Schedule',
    icon: Icons.calendar_month,
    color: MinecraftColors.grassGreen,
  ),
  MyDataGroup.study: (
    title: 'Study',
    icon: Icons.menu_book,
    color: MinecraftColors.dirtBrown,
  ),
  MyDataGroup.money: (
    title: 'Money',
    icon: Icons.account_balance_wallet,
    color: MinecraftColors.emerald,
  ),
  MyDataGroup.rewards: (
    title: 'Rewards',
    icon: Icons.star,
    color: MinecraftColors.gold,
  ),
  MyDataGroup.community: (
    title: 'Community',
    icon: Icons.groups,
    color: MinecraftColors.heartRed,
  ),
};

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({
    super.key,
    required this.user,
    required this.authService,
    this.profile,
    this.walletController,
    this.service,
    this.shareFile,
    this.documentsDir,
    required this.onBack,
    required this.onAccountDeleted,
  });

  final AuthUser user;
  final AuthService authService;

  /// The local profile (name/school cache). Null when none exists.
  final UserProfile? profile;

  /// Shared points-wallet state (null in bare widget tests).
  final PointsWalletController? walletController;

  /// Injectable service (tests pass fakes; production builds the
  /// real one from Firestore + local storage).
  final MyDataService? service;

  /// Shares the export file. Defaults to the platform share sheet;
  /// tests pass a fake that records the file instead.
  final Future<void> Function(File file)? shareFile;

  /// Where the local profile photo lives. Defaults to the real
  /// documents directory; tests pass the system temp dir so the
  /// delete flow never calls the unmocked path_provider channel
  /// (which stalls a widget test's fake-async pump loop).
  final Future<Directory> Function()? documentsDir;

  final VoidCallback onBack;

  /// Called after the account was deleted (Auth user gone): the
  /// Account tab hides this screen and signs the shell out.
  final VoidCallback onAccountDeleted;

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  late final MyDataService _service;
  var _view = _MyDataView.overview;
  MyDataSnapshot? _snapshot;
  bool _loading = true;
  String? _loadError;

  final _selected = Set<MyDataGroup>.of(MyDataGroup.values);
  bool _exporting = false;
  bool _exportReady = false;
  String? _exportError;

  final _deleteController = TextEditingController();
  var _deleteStep = _DeleteStep.warning;
  List<String>? _signInMethods;
  String? _reauthError;
  final _passwordController = TextEditingController();
  bool _reauthenticating = false;
  MyDataDeletionReport? _report;

  bool get _deleteTypedValid =>
      isMyDataDeleteConfirmationValid(_deleteController.text);

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        MyDataService(
          remoteStore: widget.authService.isConfigured
              ? FirestoreMyDataRemoteStore()
              : null,
        );
    _deleteController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _deleteController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final snapshot = await _service.collect(
        user: widget.user,
        localProfile: widget.profile,
        wallet: widget.walletController,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your data. Check your connection '
            'and try again.';
      });
    }
  }

  Future<void> _downloadGroups(Set<MyDataGroup> groups) async {
    final snapshot = _snapshot;
    if (snapshot == null || groups.isEmpty) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final json = snapshot.toJson(groups);
      final name = groups.length == 1 ? groups.single.name : 'all';
      final file = await shareMyDataJson(json, name: name);
      if (widget.shareFile != null) {
        await widget.shareFile!(file);
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      }
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportError = 'Could not prepare the export. Try again.';
      });
    }
  }

  Future<void> _startReauth() async {
    setState(() {
      _deleteStep = _DeleteStep.reauth;
      _reauthError = null;
    });
    try {
      final methods = await widget.authService.signInMethods();
      if (!mounted) return;
      setState(() => _signInMethods = methods);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _signInMethods = [];
        _reauthError = 'Could not check how you signed in. Try again.';
      });
    }
  }

  Future<void> _reauthAndDelete() async {
    final methods = _signInMethods ?? [];
    setState(() {
      _reauthenticating = true;
      _reauthError = null;
    });
    try {
      if (methods.contains('password')) {
        await widget.authService.reauthenticateWithPassword(
          password: _passwordController.text,
        );
      } else if (methods.contains('google.com')) {
        await widget.authService.reauthenticateWithGoogle();
      } else {
        throw const AuthException(
          'We could not tell how you signed in. Sign out and sign in '
          'again, then try deleting your account.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reauthenticating = false;
        _reauthError = e is AuthException
            ? e.message
            : 'Re-authentication failed. Try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _reauthenticating = false;
      _deleteStep = _DeleteStep.deleting;
    });
    final report = await _service.deleteAccount(
      user: widget.user,
      auth: widget.authService,
      reauthenticated: true,
      documentsDir: widget.documentsDir,
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _deleteStep = _DeleteStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A Material ancestor of our own: the export checkboxes
    // (CheckboxListTile) and the delete/reauth TextFields require one,
    // and this screen must not assume its host provides it — the
    // widget tests pump it bare, and a future host might too.
    // Transparent, so nothing on screen changes.
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
      key: const Key('my-data-scroll-view'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: _view == _MyDataView.overview
                    ? 'Back to Account'
                    : 'Back to My Data',
                onPressed: _view == _MyDataView.overview
                    ? widget.onBack
                    : () => setState(() {
                          _view = _MyDataView.overview;
                          _exportReady = false;
                          _exportError = null;
                        }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            switch (_view) {
              _MyDataView.overview => _overview(dark),
              _MyDataView.export => _exportView(dark),
              _MyDataView.delete => _deleteView(dark),
            },
          ],
        ),
      ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Shared bits
  // ------------------------------------------------------------------

  BoxDecoration _cardDecoration(bool dark) {
    return BoxDecoration(
      color: dark ? MinecraftColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      border: Border.all(
        color: dark ? MinecraftColors.darkBorder : MinecraftColors.border,
        width: MinecraftShapes.cardBorderWidth,
      ),
      boxShadow: const [MinecraftShapes.cardShadow],
    );
  }

  Widget _title(String title, String crumb, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: MinecraftText.heading(color: onSurface, fontSize: 22)),
        const SizedBox(height: 4),
        Text(
          crumb,
          style: MinecraftText.caption(
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _countChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6E4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      child: Text(
        label,
        style: MinecraftText.caption(
          color: MinecraftColors.deepLeaves,
          fontSize: 12,
        ).copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 1. Overview
  // ------------------------------------------------------------------

  Widget _overview(bool dark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final snapshot = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('My Data', 'Account → Privacy → My Data', onSurface),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(dark).copyWith(
            color: dark
                ? MinecraftColors.darkCard
                : const Color(0xFFEAF7DC),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What we hold about you',
                style: MinecraftText.title(color: onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'Everything EstudyanteGO stores on your account, grouped. '
                'The counts below are your real data.',
                style: MinecraftText.body(color: muted),
              ),
              const SizedBox(height: 8),
              Text(
                'Your rights under the Data Privacy Act: you can download '
                'a copy of your data anytime, and you can delete your '
                'account and everything in it. Both start right here.',
                style: MinecraftText.body(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          Column(
            children: [
              Text(_loadError!, style: MinecraftText.body(color: muted)),
              const SizedBox(height: 12),
              ElevatedButton(
                style: minecraftBlockButtonStyle(),
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ],
          )
        else if (snapshot != null)
          ...MyDataGroup.values.map((group) {
            final data = snapshot.groups[group]!;
            final meta = _groupMeta[group]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _groupCard(group, data, meta, dark, onSurface, muted),
            );
          }),
        const SizedBox(height: 4),
        ElevatedButton.icon(
          key: const Key('my-data-download-all'),
          style: minecraftBlockButtonStyle(),
          onPressed: _loading || snapshot == null
              ? null
              : () => setState(() => _view = _MyDataView.export),
          icon: const Icon(Icons.download),
          label: const Text('Download everything'),
        ),
        const SizedBox(height: 24),
        Text(
          'Danger zone',
          style: MinecraftText.title(color: MinecraftColors.heartRed),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('my-data-go-delete'),
          style: minecraftOutlinedButtonStyle().copyWith(
            foregroundColor: const WidgetStatePropertyAll(
              MinecraftColors.heartRed,
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(
                color: MinecraftColors.heartRed,
                width: MinecraftShapes.buttonBorderWidth,
              ),
            ),
            textStyle: WidgetStatePropertyAll(
              MinecraftText.button(color: MinecraftColors.heartRed),
            ),
          ),
          onPressed: () => setState(() => _view = _MyDataView.delete),
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete my account'),
        ),
      ],
    );
  }

  Widget _groupCard(
    MyDataGroup group,
    MyDataGroupData data,
    ({String title, IconData icon, Color color}) meta,
    bool dark,
    Color onSurface,
    Color muted,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(dark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: meta.color,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: MinecraftColors.border,
                width: MinecraftShapes.cardBorderWidth,
              ),
            ),
            child: Icon(meta.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      meta.title,
                      style: MinecraftText.title(color: onSurface),
                    ),
                    const SizedBox(width: 8),
                    _countChip(data.countLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Text(data.detail, style: MinecraftText.caption(color: muted)),
                if (data.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.note!,
                    style: MinecraftText.caption(
                      color: MinecraftColors.goldDark,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  key: Key('my-data-download-${group.name}'),
                  style: minecraftOutlinedButtonStyle(),
                  onPressed: _exporting
                      ? null
                      : () => _downloadGroups({group}),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 2. Export
  // ------------------------------------------------------------------

  Widget _exportView(bool dark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final snapshot = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Download my data', 'Account → Privacy → My Data', onSurface),
        Text(
          'Pick what to include, then request your export. Your data is '
          'assembled on this device into one JSON file — nothing is '
          'uploaded anywhere.',
          style: MinecraftText.body(color: muted),
        ),
        const SizedBox(height: 16),
        Text('1 · Choose what to include',
            style: MinecraftText.title(color: onSurface)),
        const SizedBox(height: 9),
        if (snapshot != null)
          ...MyDataGroup.values.map((group) {
            final data = snapshot.groups[group]!;
            final meta = _groupMeta[group]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Container(
                decoration: _cardDecoration(dark),
                // The CheckboxListTile paints its ink on the nearest
                // Material ancestor: it needs its own Material INSIDE
                // this decorated Container, or Flutter (debug) throws
                // "ListTile background color or ink splashes may be
                // invisible" — the Container's background would hide
                // ink painted on a Material above it. Transparent, so
                // the card look is unchanged.
                child: Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                  key: Key('my-data-export-${group.name}'),
                  value: _selected.contains(group),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(group);
                    } else {
                      _selected.remove(group);
                    }
                  }),
                  title: Text(
                    meta.title,
                    style: MinecraftText.title(color: onSurface),
                  ),
                  subtitle: Text(
                    data.countLabel,
                    style: MinecraftText.caption(color: muted),
                  ),
                  secondary: _countChip(data.countLabel),
                  activeColor: MinecraftColors.grassGreen,
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        Text('2 · Format', style: MinecraftText.title(color: onSurface)),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _cardDecoration(dark).copyWith(
            color: dark
                ? MinecraftColors.darkCard
                : const Color(0xFFEAF7DC),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MinecraftColors.skyBlue,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: MinecraftColors.border,
                    width: MinecraftShapes.cardBorderWidth,
                  ),
                ),
                child: const Icon(
                  Icons.data_object,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'JSON file',
                          style: MinecraftText.title(color: onSurface),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: MinecraftColors.grassGreen,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: MinecraftColors.border,
                              width: MinecraftShapes.chipBorderWidth,
                            ),
                          ),
                          child: Text(
                            'SELECTED',
                            style: MinecraftText.caption(
                              color: const Color(0xFF0E2400),
                              fontSize: 11,
                            ).copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'One JSON file with everything you picked above — '
                      'readable by apps and easy to keep as your own copy.',
                      style: MinecraftText.caption(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('3 · Request it', style: MinecraftText.title(color: onSurface)),
        const SizedBox(height: 9),
        ElevatedButton.icon(
          key: const Key('my-data-request-export'),
          style: minecraftBlockButtonStyle(),
          onPressed: _exporting || _selected.isEmpty
              ? null
              : () => _downloadGroups(Set.of(_selected)),
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download),
          label: Text(_exporting ? 'Preparing…' : 'Request export'),
        ),
        if (_exportError != null) ...[
          const SizedBox(height: 10),
          Text(
            _exportError!,
            style: MinecraftText.body(color: MinecraftColors.heartRed),
            textAlign: TextAlign.center,
          ),
        ],
        if (_exportReady) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3FBF2),
              borderRadius:
                  BorderRadius.circular(MinecraftShapes.cardRadius),
              border: Border.all(
                color: MinecraftColors.emerald,
                width: MinecraftShapes.cardBorderWidth,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your export is ready',
                  style: MinecraftText.title(
                    color: const Color(0xFF00664A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your JSON file was built on this device from the groups '
                  'you picked. Choose where to save or share it in the '
                  'share sheet.',
                  style: MinecraftText.body(
                    color: const Color(0xFF174534),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'The export is assembled on your device and shared through the '
          'system share sheet. EstudyanteGO has no export server.',
          style: MinecraftText.caption(color: muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 3. Delete
  // ------------------------------------------------------------------

  Widget _deleteView(bool dark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Delete my account', 'Account → Privacy → My Data', onSurface),
        Text(
          'Only use this if you want to leave EstudyanteGO for good. '
          'Read the warning first.',
          style: MinecraftText.body(color: muted),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDED),
            borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
            border: Border.all(
              color: const Color(0xFFD33131),
              width: MinecraftShapes.cardBorderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This cannot be undone',
                style: MinecraftText.title(
                  color: const Color(0xFFA11414),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Deleting your account erases everything below, forever. '
                'There is no backup, no recovery, and no way to get any of '
                'it back — not even by contacting support.',
                style: MinecraftText.body(
                  color: const Color(0xFF5C1D1D),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'What gets deleted forever',
          style: MinecraftText.title(color: onSurface),
        ),
        const SizedBox(height: 9),
        ..._deleteList(dark, onSurface, muted),
        const SizedBox(height: 6),
        Text(
          'Your points and credits history is an append-only ledger the '
          'app cannot erase — it stays unless Steven removes it in the '
          'Firebase Console. Your posts can only be deleted by an admin '
          'under the current rules, so they are listed in the report '
          'afterwards.',
          style: MinecraftText.caption(color: muted),
        ),
        if (_deleteStep == _DeleteStep.warning) ...[
          const SizedBox(height: 16),
          Text(
            'Type DELETE to confirm',
            style: MinecraftText.title(color: onSurface),
          ),
          const SizedBox(height: 7),
          TextField(
            key: const Key('my-data-delete-input'),
            controller: _deleteController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'DELETE',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: MinecraftColors.border,
                  width: 3,
                ),
              ),
            ),
            style: MinecraftText.title(color: onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            _deleteTypedValid
                ? 'Confirmed — the delete button is unlocked.'
                : 'The delete button unlocks only when you type the word DELETE.',
            style: MinecraftText.caption(
              color: _deleteTypedValid
                  ? MinecraftColors.deepLeaves
                  : muted,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('my-data-delete-button'),
            style: minecraftBlockButtonStyle(
              backgroundColor: MinecraftColors.heartRed,
            ),
            onPressed: _deleteTypedValid
                ? () => setState(() => _deleteStep = _DeleteStep.confirm)
                : null,
            child: const Text('Delete my account permanently'),
          ),
        ],
        if (_deleteStep == _DeleteStep.confirm) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF2B1414),
              borderRadius:
                  BorderRadius.circular(MinecraftShapes.cardRadius),
              border: Border.all(color: Colors.black, width: 3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Are you sure?',
                  style: MinecraftText.heading(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'This cannot be undone. Your profile, schedule, files, '
                  'transactions, points, posts, and messages will be '
                  'deleted forever.',
                  style: MinecraftText.body(color: const Color(0xFFFFD7D7)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  key: const Key('my-data-confirm-delete'),
                  style: minecraftBlockButtonStyle(
                    backgroundColor: MinecraftColors.heartRed,
                  ),
                  onPressed: _startReauth,
                  child: const Text('Yes, delete everything'),
                ),
                const SizedBox(height: 9),
                OutlinedButton(
                  style: minecraftOutlinedButtonStyle().copyWith(
                    backgroundColor:
                        const WidgetStatePropertyAll(Colors.white),
                  ),
                  onPressed: () =>
                      setState(() => _deleteStep = _DeleteStep.warning),
                  child: const Text('No, keep my account'),
                ),
              ],
            ),
          ),
        ],
        if (_deleteStep == _DeleteStep.reauth) _reauthCard(dark, onSurface, muted),
        if (_deleteStep == _DeleteStep.deleting) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Text(
            'Deleting your account… This takes a moment.',
            style: MinecraftText.body(color: muted),
            textAlign: TextAlign.center,
          ),
        ],
        if (_deleteStep == _DeleteStep.done && _report != null)
          _reportCard(dark, onSurface, muted),
      ],
    );
  }

  List<Widget> _deleteList(bool dark, Color onSurface, Color muted) {
    const items = [
      ('Profile and account', 'Your name, email, school, and sign-in'),
      ('Class schedule', 'Every class you saved'),
      ('Files, notes, and quizzes', 'Everything in your Study space'),
      ('Allowance transactions', 'Your full money history'),
      ('Points and streak', 'Your rewards balance and sign-in streak'),
      (
        'Posts, comments, and messages',
        'Your Community posts and Chat Support messages'
      ),
    ];
    return [
      for (final (title, sub) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: _cardDecoration(dark),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.close,
                  color: MinecraftColors.heartRed,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: MinecraftText.bodySemiBold(color: onSurface),
                      ),
                      Text(sub, style: MinecraftText.caption(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _reauthCard(bool dark, Color onSurface, Color muted) {
    final methods = _signInMethods;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One last check',
              style: MinecraftText.title(color: onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Firebase only deletes an account right after signing in. '
              'Confirm it is really you:',
              style: MinecraftText.body(color: muted),
            ),
            const SizedBox(height: 12),
            if (methods == null)
              const Center(child: CircularProgressIndicator())
            else if (methods.contains('password')) ...[
              TextField(
                key: const Key('my-data-reauth-password'),
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Your account password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                key: const Key('my-data-reauth-confirm'),
                style: minecraftBlockButtonStyle(
                  backgroundColor: MinecraftColors.heartRed,
                ),
                onPressed: _reauthenticating ? null : _reauthAndDelete,
                child: Text(
                  _reauthenticating
                      ? 'Deleting…'
                      : 'Confirm and delete my account',
                ),
              ),
            ] else if (methods.contains('google.com')) ...[
              ElevatedButton.icon(
                key: const Key('my-data-reauth-confirm'),
                style: minecraftBlockButtonStyle(
                  backgroundColor: MinecraftColors.heartRed,
                ),
                onPressed: _reauthenticating ? null : _reauthAndDelete,
                icon: const Icon(Icons.login),
                label: Text(
                  _reauthenticating
                      ? 'Deleting…'
                      : 'Confirm with Google',
                ),
              ),
            ] else ...[
              Text(
                'We could not tell how you signed in. Sign out and sign '
                'in again, then try deleting your account.',
                style: MinecraftText.body(color: muted),
              ),
            ],
            if (_reauthError != null) ...[
              const SizedBox(height: 10),
              Text(
                _reauthError!,
                style: MinecraftText.body(color: MinecraftColors.heartRed),
              ),
            ],
            const SizedBox(height: 9),
            TextButton(
              onPressed: _reauthenticating
                  ? null
                  : () => setState(() => _deleteStep = _DeleteStep.warning),
              child: const Text('Cancel — keep my account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(bool dark, Color onSurface, Color muted) {
    final report = _report!;
    final authDeleted = report.items.any(
      (i) =>
          i.label == 'Sign-in account' &&
          i.outcome == MyDataDeletionOutcome.deleted,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              authDeleted
                  ? 'Your account has been deleted'
                  : 'Deletion finished with problems',
              style: MinecraftText.title(color: onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              authDeleted
                  ? 'Everything below is what happened to your data. '
                      'Items marked "kept" still exist — see the note.'
                  : 'Some steps failed (see below). Your sign-in account '
                      'is still active — sign in again and try, or ask '
                      'Steven for help.',
              style: MinecraftText.body(color: muted),
            ),
            const SizedBox(height: 12),
            ...report.items.map((item) {
              final (icon, color) = switch (item.outcome) {
                MyDataDeletionOutcome.deleted =>
                  (Icons.check_circle, MinecraftColors.deepLeaves),
                MyDataDeletionOutcome.kept =>
                  (Icons.warning_amber, MinecraftColors.goldDark),
                MyDataDeletionOutcome.failed =>
                  (Icons.error, MinecraftColors.heartRed),
              };
              final label = switch (item.outcome) {
                MyDataDeletionOutcome.deleted => 'Deleted',
                MyDataDeletionOutcome.kept => 'Kept',
                MyDataDeletionOutcome.failed => 'Failed',
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label — ${item.label}',
                            style: MinecraftText.bodySemiBold(
                              color: onSurface,
                            ),
                          ),
                          if (item.note != null)
                            Text(
                              item.note!,
                              style: MinecraftText.caption(color: muted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('my-data-deletion-done'),
              style: minecraftBlockButtonStyle(),
              onPressed: authDeleted
                  ? widget.onAccountDeleted
                  : widget.onBack,
              child: Text(authDeleted ? 'Done' : 'Back to Account'),
            ),
          ],
        ),
      ),
    );
  }
}
