// Floating "Rate this EstudyanteGO App" UI (Nov 9, 2026).
//
// Lives in the app shell (lib/main.dart wraps both Scaffold bodies
// with [AppRatingOverlay]) so the pill floats over EVERY tab —
// Student, Study, Fares, Map, Communities, Account — and the card
// opens over the current screen, returning to the same tab on close.
//
// Design = the approved preview `rate-this-estudyantego-app-preview`,
// matched exactly ("gayang gaya"): the pill sits right-aligned
// (right 16, bottom 88) with a #34d399 → #16a34a gradient, dark text
// and a dark star badge, bobbing gently; the card is a bottom sheet
// (left/right 12, bottom 12) with a drag handle, an E-logo header
// naming the tab it floats over, and a footer; the "Thank you!"
// popup is the shared top popup (top 38, left/right 14) with the
// star count in its subtitle. No emoji icons — Material icons only
// (star, sentiment_satisfied / sentiment_dissatisfied, check,
// close, send, build).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_rating.dart';
import 'minecraft_theme.dart';
import 'top_popup.dart';

/// The improve topics offered in the "What can we improve?" step.
/// Labels match the approved preview exactly. The admin reviews
/// screen reuses this list for its topic filter, so the two stay
/// in sync.
const List<String> appRatingTopics = <String>[
  'Map & Routes',
  'Fares',
  'Live Follow',
  'App Speed',
  'Bugs & Crashes',
  'Design',
  'Notifications',
  'Student Features',
  'Something Else',
];

/// Material icon for each improve topic (the preview chips carry one).
const Map<String, IconData> appRatingTopicIcons = <String, IconData>{
  'Map & Routes': Icons.map,
  'Fares': Icons.payments,
  'Live Follow': Icons.my_location,
  'App Speed': Icons.speed,
  'Bugs & Crashes': Icons.bug_report,
  'Design': Icons.design_services,
  'Notifications': Icons.notifications,
  'Student Features': Icons.school,
  'Something Else': Icons.more_horiz,
};

/// How long the "Thank you!" popup stays up after sending.
const Duration appRatingThanksDuration = Duration(seconds: 5);

/// Maximum comment length (preview: 500 characters).
const int appRatingCommentMaxLength = 500;

/// Delay between the 3rd action unlocking the prompt and the card
/// popping up on its own (preview: 900ms). The pill itself appears
/// immediately on unlock; only the auto-open waits.
const Duration appRatingAutoOpenDelay = Duration(milliseconds: 900);

// Preview colors — the rating card is dark in either app theme, so
// these are fixed, not theme-derived. Minecraft palette (Nov 12,
// 2026 audit): the dark surfaces are the Minecraft dark tokens and
// the brand greens are grass / deep leaves.
const Color _appText = Color(0xFFEEF7F0);
const Color _appTextSoft = MinecraftColors.darkSubtext;
const Color _appSurface = MinecraftColors.darkBackground;
const Color _appSurface2 = MinecraftColors.darkElevated;
const Color _appLine = MinecraftColors.darkBorder;
const Color _appBrand = MinecraftColors.grassGreen;
const Color _appBrandDeep = MinecraftColors.deepLeaves;
const Color _starOn = MinecraftColors.gold;
const Color _starOff = MinecraftColors.darkBorder;
const Color _cardBg = MinecraftColors.darkCard;
const Color _cardBorder = MinecraftColors.darkBorder;
const Color _placeholderColor = MinecraftColors.darkSubtext;

/// Rating words, one per star (preview).
const List<String> _ratingWords = <String>[
  'Poor',
  'Fair',
  'Good',
  'Very Good',
  'Excellent',
];

/// Hint line under the stars, one per star (preview).
const List<String> _ratingHints = <String>[
  'Sorry to hear that — tell us what to fix below.',
  'Thanks for the honesty — help us do better below.',
  'Thanks! Tell us what would make it a 5 below.',
  "Glad it's working well for you!",
  'Salamat! Glad EstudyanteGO helps your commute.',
];

/// Improve-panel intro lines by rating band: low (1–2 stars),
/// mid (3 stars), high (4–5 stars). The "Not yet" path starts on
/// the low intro.
const List<String> _improveIntros = <String>[
  "Sorry your trip with the app wasn't great. Pick what went wrong and we'll work on it first.",
  'Pick the parts of the app you want us to make better. You can choose more than one.',
  "Even good trips can get better. Pick anything you'd still like improved — or skip and just send your rating.",
];

/// Comment placeholder by rating band (preview).
const List<String> _commentPlaceholders = <String>[
  'What went wrong? Tell us so we can fix it.',
  'What would make this a 5-star app for you?',
  'What did you love — and what could still be better?',
];

/// Rating band: 0 = low (1–2 stars), 1 = mid (3 stars),
/// 2 = high (4–5 stars).
int _ratingBand(int stars) => stars <= 2 ? 0 : stars == 3 ? 1 : 2;

/// Floating rating UI over the shell's tab content: the emerald
/// pill, the "Satisfied?" bottom sheet over a dimmed scrim, and the
/// 5-second top "Thank you!" popup.
///
/// The pill appears only once the tracker unlocks (3 real actions)
/// and the student has not rated for this version; the card pops
/// up once automatically 900ms after that moment. After a
/// successful send the pill disappears completely (one-time only
/// per app version).
class AppRatingOverlay extends StatefulWidget {
  const AppRatingOverlay({
    super.key,
    required this.child,
    this.tracker,
    this.currentUserId,
    this.currentTabLabel = 'Student',
  });

  final Widget child;

  /// Defaults to [AppRatingTracker.instance]; tests pass their own.
  final AppRatingTracker? tracker;

  /// Firebase UID of the signed-in student, or null when signed out.
  final String? currentUserId;

  /// Label of the tab the overlay floats over ("Student", "Study",
  /// "Fares", "Map", "Communities", "Account") — shown in the card
  /// header as "Floating over the `<Tab>` screen".
  final String currentTabLabel;

  @override
  State<AppRatingOverlay> createState() => _AppRatingOverlayState();
}

class _AppRatingOverlayState extends State<AppRatingOverlay>
    with TickerProviderStateMixin {
  late final AppRatingTracker _tracker =
      widget.tracker ?? AppRatingTracker.instance;
  late final AnimationController _thanksController;
  late final AnimationController _sheetController;
  late final Animation<double> _sheetAnimation;
  bool _cardOpen = false;
  bool _autoOpened = false;
  bool _showThanks = false;
  int? _thanksStars;
  Timer? _autoOpenTimer;

  @override
  void initState() {
    super.initState();
    _thanksController = AnimationController(
      vsync: this,
      duration: appRatingThanksDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showThanks = false);
        }
      });
    _sheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _sheetAnimation = CurvedAnimation(
      parent: _sheetController,
      curve: const Cubic(0.22, 1, 0.36, 1),
    );
    _tracker.addListener(_onTrackerChanged);
    unawaited(_tracker.ensureInitialized());
    // The tracker may already be unlocked (restored state, or a
    // test that recorded actions before pumping): check once after
    // the first frame, as well as on every notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTrackerChanged());
  }

  @override
  void dispose() {
    _autoOpenTimer?.cancel();
    _tracker.removeListener(_onTrackerChanged);
    _thanksController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _onTrackerChanged() {
    // The prompt unlocked: pop the card up once, this session,
    // 900ms after the 3rd action (preview delay). The pill itself
    // appears immediately on unlock. If the student closes the
    // card without rating, the pill stays and they can reopen it;
    // it does not auto-pop again.
    if (_tracker.showPrompt && !_autoOpened && mounted) {
      _autoOpened = true;
      _autoOpenTimer = Timer(appRatingAutoOpenDelay, () {
        if (mounted && _tracker.showPrompt) _openCard();
      });
    }
  }

  void _openCard() {
    setState(() {
      _autoOpened = true;
      _cardOpen = true;
    });
    _sheetController.forward();
  }

  void _closeCard() {
    // Dismiss the keyboard first: the sheet stays mounted (draft
    // persistence), so an open keyboard would otherwise linger.
    FocusScope.of(context).unfocus();
    setState(() => _cardOpen = false);
    _sheetController.reverse();
  }

  /// Sends the rating; on success closes the card and shows the
  /// 5-second "Thank you!" popup. Returns whether the write
  /// succeeded (the card shows an honest error when it did not).
  Future<bool> _submit(AppRatingSubmission submission) async {
    final ok = await _tracker.submit(submission);
    if (!mounted) return ok;
    if (ok) {
      setState(() {
        _cardOpen = false;
        _showThanks = true;
        _thanksStars = submission.stars;
      });
      _sheetController.reverse();
      _thanksController.forward(from: 0);
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetMaxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 52
            : 600.0;
        return AnimatedBuilder(
          animation: _tracker,
          child: widget.child,
          builder: (context, child) {
            final showPill = _tracker.showPrompt && !_cardOpen;
            return Stack(
              children: [
                child!,
                // Dimmed scrim (preview: rgba(3,8,5,0.62), 0.3s fade).
                AnimatedOpacity(
                  opacity: _cardOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_cardOpen,
                    child: GestureDetector(
                      onTap: _closeCard,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        color: const Color.fromRGBO(3, 8, 5, 0.62),
                      ),
                    ),
                  ),
                ),
                // Bottom sheet — always mounted so a draft survives
                // closing without sending (preview: "keeps the
                // button and the draft"). Offstage while closed, so
                // it is invisible, untouchable, and skipped by
                // finders; the slide + fade animation plays on open.
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Offstage(
                    offstage: !_cardOpen,
                    child: AnimatedBuilder(
                      animation: _sheetAnimation,
                      builder: (context, sheetChild) {
                        final t = _sheetAnimation.value;
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 28 * (1 - t)),
                            child: Transform.scale(
                              scale: 0.97 + 0.03 * t,
                              child: sheetChild,
                            ),
                          ),
                        );
                      },
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: sheetMaxHeight),
                        child: _RatingCard(
                          currentUserId: widget.currentUserId,
                          currentTabLabel: widget.currentTabLabel,
                          onSubmit: _submit,
                          onClose: _closeCard,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showThanks)
                  Positioned(
                    top: 38,
                    left: 14,
                    right: 14,
                    child: TopPopup(
                      progress: _thanksController,
                      title: 'Thank you!',
                      message: _thanksStars != null
                          ? 'Your $_thanksStars-star feedback was sent.'
                          : 'Your feedback was sent.',
                    ),
                  ),
                if (showPill)
                  Positioned(
                    right: 16,
                    bottom: 88,
                    child: _RatePill(onTap: _openCard),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The floating emerald pill: "Rate this app" + star badge.
/// Right-aligned above the bottom nav (preview: right 16,
/// bottom 88); gradient #34d399 → #16a34a, dark text, dark star
/// badge with an amber star, bobbing gently (3.2s). Hidden while
/// the card is open.
class _RatePill extends StatefulWidget {
  const _RatePill({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RatePill> createState() => _RatePillState();
}

class _RatePillState extends State<_RatePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;
  bool _bobStarted = false;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bobStarted) {
      _bobStarted = true;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _bobController.repeat();
      }
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bobController,
      builder: (context, child) {
        // Preview bob: translateY 0 → -5px → 0 over 3.2s, ease-in-out.
        final dy = -5 * math.sin(math.pi * _bobController.value);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  MinecraftColors.emerald,
                  MinecraftColors.grassGreen,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color:
                      MinecraftColors.grassGreen.withValues(alpha: 0.55),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                  spreadRadius: -8,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          const Color(0xFF07130C).withValues(alpha: 0.92),
                    ),
                    child: const Icon(
                      Icons.star,
                      color: _starOn,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Text(
                    'Rate this app',
                    style: TextStyle(
                      color: Color(0xFF07130C),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating rating card, rebuilt as the preview's bottom sheet:
/// drag handle, E-logo header naming the tab it floats over,
/// scrollable body, and a footer with the Send button. Opens with
/// ONE question first — "Satisfied?" — then reveals stars ("Yes,
/// satisfied") or jumps straight to "What can we improve?"
/// ("Not yet"). Closing returns to the same tab; the card stays
/// mounted while closed, so a draft survives reopening.
class _RatingCard extends StatefulWidget {
  const _RatingCard({
    required this.currentUserId,
    required this.currentTabLabel,
    required this.onSubmit,
    required this.onClose,
  });

  final String? currentUserId;
  final String currentTabLabel;
  final Future<bool> Function(AppRatingSubmission submission) onSubmit;
  final VoidCallback onClose;

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  bool? _satisfied;
  int? _stars;
  final Set<String> _topics = <String>{};
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_onCommentChanged);
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  /// Re-evaluates the Send button and the comment counter as the
  /// student types (the "Not yet" path can send on a comment alone).
  void _onCommentChanged() {
    if (mounted) setState(() {});
  }

  /// The star row shows once Satisfied? is answered — on both
  /// paths (preview: the prompt line, stars, word and hint live in
  /// the section that opens after the answer).
  bool get _showStars => _satisfied != null;

  bool get _showImprove =>
      _satisfied == false || (_satisfied == true && _stars != null);

  /// Prompt line above the stars (preview).
  String get _rateMini {
    if (_satisfied == false) {
      return 'Sorry to hear that — what should we fix?';
    }
    if (_satisfied == true) return 'Great! How would you rate it?';
    return 'How would you rate it?';
  }

  /// Improve-panel intro, by rating band (preview). "Not yet"
  /// starts on the low intro; picking stars switches it to the
  /// picked band.
  String get _improveIntro {
    if (_stars != null) return _improveIntros[_ratingBand(_stars!)];
    if (_satisfied == false) return _improveIntros[0];
    return _improveIntros[1];
  }

  /// Comment placeholder, by rating band (preview).
  String get _commentPlaceholder {
    if (_stars != null) {
      return _commentPlaceholders[_ratingBand(_stars!)];
    }
    if (_satisfied == false) return _commentPlaceholders[0];
    return _commentPlaceholders[1];
  }

  /// Send rule — unchanged from the build: "Yes, satisfied" needs
  /// stars; "Not yet" needs topics and/or a comment.
  bool get _canSend {
    if (_satisfied == null || _submitting) return false;
    if (_satisfied == true) return _stars != null;
    return _topics.isNotEmpty || _commentController.text.trim().isNotEmpty;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final submission = AppRatingSubmission(
      satisfied: _satisfied!,
      stars: _stars,
      topics: _topics.toList(),
      comment: _commentController.text.trim(),
      userId: widget.currentUserId,
      appVersion: appRatingVersion,
    );
    final ok = await widget.onSubmit(submission);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      setState(() {
        _error =
            "Couldn't send your feedback. Check your connection and try again.";
      });
    } else {
      // Sent: the prompt is used up for this version and the pill
      // is gone, so the card can never reopen — clear the draft.
      _resetDraft();
    }
  }

  void _resetDraft() {
    setState(() {
      _satisfied = null;
      _stars = null;
      _topics.clear();
      _commentController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle (preview: 44×5, #33503e).
          Align(
            alignment: Alignment.center,
            child: Container(
              key: const Key('rating-drag-handle'),
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 2),
              decoration: BoxDecoration(
                color: _starOff,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          // Header: E-logo badge, title + "Floating over the X
          // screen", close.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                const _LogoBadge(),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rate EstudyanteGO',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _appText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 10,
                            color: _starOn,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Floating over the ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _appTextSoft,
                                    ),
                                  ),
                                  TextSpan(
                                    text: widget.currentTabLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _appBrand,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' screen',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _appTextSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _appSurface,
                    border: Border.all(color: _appLine),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 13,
                      color: _appTextSoft,
                    ),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    onPressed: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
          // Scrollable body.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 2),
                  const Text(
                    'Satisfied?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19.5,
                      fontWeight: FontWeight.w800,
                      color: _appText,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: const Text(
                        'Are you satisfied with EstudyanteGO? Tap one — then the stars and “what to improve” appear.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: _appTextSoft,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SatisfiedButton(
                          icon: Icons.sentiment_satisfied,
                          label: 'Yes, satisfied',
                          selected: _satisfied == true,
                          selectedBackground: _appBrandDeep,
                          selectedBorder: _appBrand,
                          selectedIconColor: const Color(0xFFBBF7D0),
                          onTap: () => setState(() => _satisfied = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SatisfiedButton(
                          icon: Icons.sentiment_dissatisfied,
                          label: 'Not yet',
                          selected: _satisfied == false,
                          selectedBackground: const Color(0xFF92400E),
                          selectedBorder: _starOn,
                          selectedIconColor: const Color(0xFFFDE68A),
                          onTap: () => setState(() => _satisfied = false),
                        ),
                      ),
                    ],
                  ),
                  if (_showStars) ...[
                    const SizedBox(height: 15),
                    Text(
                      _rateMini,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _appText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            icon: Icon(
                              i <= (_stars ?? 0)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: i <= (_stars ?? 0)
                                  ? _starOn
                                  : _starOff,
                              size: 38,
                            ),
                            padding: const EdgeInsets.all(4),
                            tooltip:
                                'Rate $i star${i == 1 ? '' : 's'}',
                            onPressed: () => setState(() => _stars = i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      height: 23,
                      child: Center(
                        child: Text(
                          _stars == null
                              ? ''
                              : _ratingWords[_stars! - 1],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _starOn,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 15,
                      child: Center(
                        child: Text(
                          _stars == null
                              ? 'No rating yet — tap a star'
                              : _ratingHints[_stars! - 1],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _appTextSoft,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_showImprove) ...[
                    const SizedBox(height: 15),
                    Container(
                      decoration: BoxDecoration(
                        color: _appSurface,
                        border: Border.all(color: _appLine),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.build,
                                size: 13,
                                color: _appBrand,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'What can we improve?',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: _appText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _improveIntro,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: _appTextSoft,
                            ),
                          ),
                          const SizedBox(height: 11),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final topic in appRatingTopics)
                                _TopicChip(
                                  label: topic,
                                  icon: appRatingTopicIcons[topic] ??
                                      Icons.label,
                                  selected: _topics.contains(topic),
                                  onTap: () {
                                    setState(() {
                                      if (_topics.contains(topic)) {
                                        _topics.remove(topic);
                                      } else {
                                        _topics.add(topic);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Tell us more ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _appText,
                                  ),
                                ),
                                TextSpan(
                                  text: '(optional)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _appTextSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _commentController,
                            maxLength: appRatingCommentMaxLength,
                            maxLines: 5,
                            minLines: 3,
                            textCapitalization:
                                TextCapitalization.sentences,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: _appText,
                            ),
                            decoration: InputDecoration(
                              hintText: _commentPlaceholder,
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: _placeholderColor,
                              ),
                              filled: true,
                              fillColor: MinecraftColors.darkBackground,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 10,
                              ),
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _appLine),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _appLine),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _appBrand),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${_commentController.text.length} / $appRatingCommentMaxLength',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: _appTextSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: MinecraftColors.heartRed),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Footer: Send button + foot note (preview: top border).
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _appLine)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _appBrandDeep,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _appSurface2,
                    disabledForegroundColor: _placeholderColor,
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Sending…' : 'Send Feedback'),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Floating card — close it with the X or the dimmed area and the screen underneath stays exactly as it was.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: _appTextSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 44px E-logo badge (preview): gradient #22c55e → #14532d rounded
/// square with a white "E". The preview's small graduation-cap mark
/// was REMOVED Nov 9, 2026 at Steven's direction ("Tanggalin yung
/// cap") — the cap is wrong per his rule; the badge is now the plain
/// E logo, matching the real logo.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            MinecraftColors.grassGreen,
            MinecraftColors.deepLeaves,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(13)),
      ),
      alignment: Alignment.center,
      child: const Text(
        'E',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// One of the two big "Satisfied?" answers: a bordered toggle with
/// an icon + label. Colors match the preview: unselected is the
/// dark surface with a line border; selected is filled with the
/// answer's color (green for "Yes, satisfied", amber-brown for
/// "Not yet").
class _SatisfiedButton extends StatelessWidget {
  const _SatisfiedButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedBorder,
    required this.selectedIconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedBorder;
  final Color selectedIconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contentColor = selected ? Colors.white : _appText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? selectedBackground : _appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? selectedBorder : _appLine,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 15, 8, 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: selected ? selectedIconColor : _appTextSoft,
                  size: 26,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: contentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One improve-topic chip (preview): dark pill with a small icon
/// and label; selected = green fill + white text.
class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? _appBrandDeep : _appSurface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _appBrand : _appLine,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 11,
                color: selected
                    ? const Color(0xFFBBF7D0)
                    : _appTextSoft,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _appText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// (The 5-second "Thank you!" popup is the shared [TopPopup] —
/// see `top_popup.dart` — shown by the overlay above.)
