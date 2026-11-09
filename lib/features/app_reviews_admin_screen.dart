// App Reviews — admin screen (Nov 9, 2026).
//
// Account → Admin Access → "App Reviews". ADMIN-ONLY: the tile is
// shown only to the allowlisted admin emails (admin_access.dart)
// and Firestore rules enforce read access server-side.
//
// Summary (average rating, total reviews, Satisfied %,
// star-distribution bars 5★→1★), filters (stars / topic /
// Satisfied? answer) that actually filter the list, and the review
// list, newest first. Each card shows the stars (when given), a
// Satisfied badge, topic chips, the comment, the date, the app
// version, and a reply count. The reviewer is shown only as
// "Student" (anonymous — no names, for privacy). Tapping a review
// opens the detail view with the full review, the Admin comments
// thread, and a composer.

import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'app_rating_overlay.dart' show appRatingTopics;
import 'app_review_detail_screen.dart';
import 'app_reviews.dart';
import 'student/student_data.dart';

/// The App Reviews list screen (body only — the Account tab wraps
/// it in a Scaffold with an AppBar titled "App Reviews").
class AppReviewsScreen extends StatefulWidget {
  const AppReviewsScreen({
    super.key,
    required this.repository,
    required this.adminEmail,
  });

  /// Null when Firebase is not configured — the screen then shows
  /// an honest "unavailable" state instead of crashing.
  final AppReviewsRepository? repository;

  /// The signed-in admin's email (recorded on each reply).
  final String? adminEmail;

  @override
  State<AppReviewsScreen> createState() => _AppReviewsScreenState();
}

class _AppReviewsScreenState extends State<AppReviewsScreen> {
  /// Star filter: null = All, -1 = No star, 1–5 = that many stars.
  int? _starFilter;

  /// Topic filter: null = All topics.
  String? _topicFilter;

  /// Satisfied filter: null = All, true = Satisfied, false = Not yet.
  bool? _satisfiedFilter;

  /// The ratings stream, created once — never in build, or every
  /// rebuild would resubscribe and re-emit.
  Stream<List<AppRating>>? _ratingsStream;

  @override
  void initState() {
    super.initState();
    _ratingsStream = widget.repository?.watchAll();
  }

  bool get _hasActiveFilters =>
      _starFilter != null ||
      _topicFilter != null ||
      _satisfiedFilter != null;

  void _clearFilters() {
    setState(() {
      _starFilter = null;
      _topicFilter = null;
      _satisfiedFilter = null;
    });
  }

  List<AppRating> _filtered(List<AppRating> ratings) {
    return ratings.where((rating) {
      if (_starFilter != null) {
        if (_starFilter == -1) {
          if (rating.stars != null) return false;
        } else if (rating.stars != _starFilter) {
          return false;
        }
      }
      if (_topicFilter != null &&
          !rating.topics.contains(_topicFilter)) {
        return false;
      }
      if (_satisfiedFilter != null &&
          rating.satisfied != _satisfiedFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  void _openDetail(AppRating rating) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Review')),
          body: AppReviewDetailScreen(
            repository: widget.repository,
            ratingId: rating.id,
            adminEmail: widget.adminEmail,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Padding(
          padding: AppLayout.pagePaddingLarge,
          child: Text(
            'App reviews are unavailable — the app is not connected to Firebase.',
          ),
        ),
      );
    }
    return StreamBuilder<List<AppRating>>(
      stream: _ratingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: AppLayout.pagePaddingLarge,
              child: Text(
                "Couldn't load app reviews. Try again.",
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ratings = snapshot.data ?? const <AppRating>[];
        if (ratings.isEmpty) {
          return const Center(
            child: Padding(
              padding: AppLayout.pagePaddingLarge,
              child: Text(
                'No reviews yet. When students send feedback, it will appear here.',
              ),
            ),
          );
        }
        final filtered = _filtered(ratings);
        return Column(
          children: [
            _SummaryCard(ratings: ratings),
            _Filters(
              starFilter: _starFilter,
              onStarFilter: (value) {
                setState(() => _starFilter = value);
              },
              topicFilter: _topicFilter,
              onTopicFilter: (value) {
                setState(() => _topicFilter = value);
              },
              satisfiedFilter: _satisfiedFilter,
              onSatisfiedFilter: (value) {
                setState(() => _satisfiedFilter = value);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} ${filtered.length == 1 ? 'review' : 'reviews'}',
                    style: AppText.labelStrong,
                  ),
                  const Spacer(),
                  if (_hasActiveFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: AppLayout.pagePaddingLarge,
                        child: Text(
                          'No reviews match these filters.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final rating = filtered[index];
                        return _ReviewCard(
                          rating: rating,
                          onTap: () => _openDetail(rating),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Summary: average rating, total reviews, Satisfied %, and the
/// star-distribution bars (5★→1★).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.ratings});

  final List<AppRating> ratings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final starred = ratings.where((r) => r.stars != null).toList();
    final average = starred.isEmpty
        ? null
        : starred.map((r) => r.stars!).reduce((a, b) => a + b) /
            starred.length;
    final satisfiedCount = ratings.where((r) => r.satisfied).length;
    final satisfiedPct = ratings.isEmpty
        ? 0
        : (satisfiedCount * 100 / ratings.length).round();
    final noStarCount = ratings.length - starred.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        average == null
                            ? '—'
                            : average.toStringAsFixed(1),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Icon(
                          Icons.star,
                          color: Color(0xFFFFB300),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  label: average == null
                      ? 'No star ratings yet'
                      : 'Average rating',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: Text(
                    '${ratings.length}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  label: 'Total reviews',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: Text(
                    '$satisfiedPct%',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  label: 'Satisfied',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var stars = 5; stars >= 1; stars--)
            _DistributionRow(
              stars: stars,
              count: ratings.where((r) => r.stars == stars).length,
              total: ratings.length,
            ),
          if (noStarCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$noStarCount ${noStarCount == 1 ? 'review' : 'reviews'} without stars',
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final Widget value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        value,
        Text(
          label,
          style: AppText.caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.stars,
    required this.count,
    required this.total,
  });

  final int stars;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$stars★',
              style: AppText.labelStrong,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: const Color(0xFFFFB300),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// The three filters: stars (chips), topic (dropdown), Satisfied?
/// (segmented). They combine — a review must match all of them.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.starFilter,
    required this.onStarFilter,
    required this.topicFilter,
    required this.onTopicFilter,
    required this.satisfiedFilter,
    required this.onSatisfiedFilter,
  });

  final int? starFilter;
  final ValueChanged<int?> onStarFilter;
  final String? topicFilter;
  final ValueChanged<String?> onTopicFilter;
  final bool? satisfiedFilter;
  final ValueChanged<bool?> onSatisfiedFilter;

  static const _starOptions = <int?, String>{
    null: 'All',
    5: '5★',
    4: '4★',
    3: '3★',
    2: '2★',
    1: '1★',
    -1: 'No star',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _starOptions.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: starFilter == entry.key,
                      onSelected: (_) => onStarFilter(entry.key),
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: starFilter == entry.key
                            ? Colors.white
                            : scheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: topicFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Topic',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All topics'),
              ),
              for (final topic in appRatingTopics)
                DropdownMenuItem<String>(
                  value: topic,
                  child: Text(topic),
                ),
            ],
            onChanged: onTopicFilter,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool?>(
            segments: const [
              ButtonSegment<bool?>(value: null, label: Text('All')),
              ButtonSegment<bool?>(
                value: true,
                label: Text('Satisfied'),
              ),
              ButtonSegment<bool?>(
                value: false,
                label: Text('Not yet'),
              ),
            ],
            selected: {satisfiedFilter},
            onSelectionChanged: (selection) {
              onSatisfiedFilter(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

/// One review in the list: stars, Satisfied badge, topic chips,
/// comment, date, app version, reviewer ("Student") and reply
/// count. Tapping opens the detail view.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.rating, required this.onTap});

  final AppRating rating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final submittedAt = rating.submittedAt;
    final satisfied = rating.satisfied;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (rating.stars != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= rating.stars!
                                ? Icons.star
                                : Icons.star_border,
                            color: const Color(0xFFFFB300),
                            size: 18,
                          ),
                      ],
                    )
                  else
                    const Text('No stars', style: AppText.caption),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: satisfied
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      satisfied ? 'Satisfied' : 'Not yet',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (submittedAt != null)
                    Text(
                      formatDate(submittedAt),
                      style: AppText.caption,
                    ),
                ],
              ),
              if (rating.topics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final topic in rating.topics)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(topic, style: AppText.small),
                      ),
                  ],
                ),
              ],
              if (rating.comment.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(rating.comment, style: AppText.body),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const Text('Student', style: AppText.caption),
                  if (rating.appVersion.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'v${rating.appVersion}',
                      style: AppText.caption,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    Icons.comment_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  Text(
                    rating.replyCount == 0
                        ? 'No replies yet'
                        : '${rating.replyCount} ${rating.replyCount == 1 ? 'reply' : 'replies'}',
                    style: AppText.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
