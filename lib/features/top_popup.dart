// One shared top popup (Nov 9, 2026) — the app-wide replacement
// for every bottom white-bar SnackBar, and the single visual used
// by the rating "Thank you!" popup and the admin-reply popup.
//
// A dark card at the top of the screen: green checkmark circle,
// title (optional), message, optional action, and a green bar at
// the bottom that drains over 5 seconds, then auto-dismisses.
//
// Presentation only — every message's TEXT is kept exactly as it
// was in the SnackBar it replaces; only the white bar at the
// bottom becomes this dark card at the top. No wording changes,
// no behavior changes except the presentation. The two SnackBar
// actions ("Open Settings", "View hidden") survive as the popup's
// optional action button, so tapping still runs them.
//
// Two ways to show it:
//  * [TopPopup.show] — from any BuildContext (overlays the whole
//    app via the root Overlay, so it works from onboarding screens
//    and the shell alike). This is what every former SnackBar
//    call site uses. One popup at a time: showing a new one
//    replaces the current one, like a SnackBar.
//  * [TopPopup] widget directly — for the rating and reply
//    overlays, which already own their own animation controller
//    and position the popup inside the shell's Stack.

import 'package:flutter/material.dart';

import 'app_layout.dart';

/// How long a top popup stays up before auto-dismissing.
const Duration topPopupDuration = Duration(seconds: 5);

/// The shared top-popup card: dark card, green checkmark circle,
/// title, message, optional action, green drain bar.
///
/// [progress] is a 0→1 animation over [topPopupDuration]; the
/// drain bar shows `1 - progress`. The caller owns the controller
/// (the rating/reply overlays) or [TopPopup.show] owns it (the
/// SnackBar replacement path).
class TopPopup extends StatelessWidget {
  const TopPopup({
    super.key,
    required this.progress,
    this.title,
    required this.message,
    this.messageMaxLines,
    this.onTap,
    this.actionLabel,
    this.onAction,
  });

  /// The 0→1 animation driving the drain bar (5 seconds).
  final Animation<double> progress;

  /// Bold heading line. Null for plain SnackBar messages, which
  /// carry their whole text in [message] (no title invented).
  final String? title;

  /// The message text — kept exactly as the SnackBar had it.
  final String message;

  /// Max lines for the message (reply snippet = 2, ellipsis).
  /// Null = wrap fully (SnackBar messages show in full).
  final int? messageMaxLines;

  /// Tapping the popup (reply popup opens the Notifications sheet).
  final VoidCallback? onTap;

  /// Optional action label (the old SnackBarAction label, e.g.
  /// "Open Settings", "View hidden").
  final String? actionLabel;

  /// Runs when the action is tapped.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Preview geometry: 1px #22c55e border, 16px radius, content
    // padding 12/14/15, and the 3px #22c55e drain bar pinned to the
    // bottom edge (not in-flow under the text).
    final content = Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(title!, style: AppText.heading),
                        Text(
                          message,
                          style: AppText.body,
                          maxLines: messageMaxLines,
                          overflow: messageMaxLines == null
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: AnimatedBuilder(
            animation: progress,
            builder: (context, _) => LinearProgressIndicator(
              value: 1 - progress.value,
              color: const Color(0xFF22C55E),
              backgroundColor: Colors.transparent,
              minHeight: 3,
            ),
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFF22C55E)),
    );
    if (onTap == null) {
      return Material(
        elevation: 4,
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: content,
      );
    }
    return Material(
      elevation: 4,
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      ),
    );
  }

  /// The popup currently shown by [show], if any. Showing a new
  /// popup replaces it (same as a SnackBar replacing the current
  /// one).
  static OverlayEntry? _currentEntry;

  /// Shows the shared top popup from any [BuildContext] — the
  /// drop-in replacement for `ScaffoldMessenger.of(context)
  /// .showSnackBar(...)`. Inserts into the root Overlay so it
  /// appears at the top of the screen above everything (shell,
  /// onboarding, dialogs), auto-dismisses after 5 seconds.
  ///
  /// [message] is the exact SnackBar text, unchanged. [title] is
  /// null for SnackBar replacements (no title invented); the
  /// rating/reply popups pass their own title.
  static void show(
    BuildContext context, {
    String? title,
    required String message,
    int? messageMaxLines,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = topPopupDuration,
  }) {
    _currentEntry?.remove();
    _currentEntry = null;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (entryContext) => _TopPopupEntry(
        title: title,
        message: message,
        messageMaxLines: messageMaxLines,
        onTap: onTap,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onDismiss: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

/// The OverlayEntry's widget: owns the 5-second drain animation,
/// positions the popup just below the status bar, and removes the
/// entry when the animation completes (or when tapped / actioned).
class _TopPopupEntry extends StatefulWidget {
  const _TopPopupEntry({
    required this.title,
    required this.message,
    required this.messageMaxLines,
    required this.onTap,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onDismiss,
  });

  final String? title;
  final String message;
  final int? messageMaxLines;
  final VoidCallback? onTap;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_TopPopupEntry> createState() => _TopPopupEntryState();
}

class _TopPopupEntryState extends State<_TopPopupEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _dismiss();
      });
    // Start the drain now: the entry is built in the same frame the
    // popup appears, so the 5 seconds run from when it shows.
    // (A post-frame callback was tried first — it never fired for an
    // OverlayEntry child in tests, so the drain never started.)
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: TopPopup(
        progress: _controller,
        title: widget.title,
        message: widget.message,
        messageMaxLines: widget.messageMaxLines,
        onTap: widget.onTap == null
            ? null
            : () {
                final onTap = widget.onTap;
                _dismiss();
                onTap?.call();
              },
        actionLabel: widget.actionLabel,
        onAction: widget.onAction == null
            ? null
            : () {
                final onAction = widget.onAction;
                _dismiss();
                onAction?.call();
              },
      ),
    );
  }
}
