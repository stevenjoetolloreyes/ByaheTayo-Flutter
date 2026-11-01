import 'package:byahetayo/features/community_admin.dart';
import 'package:byahetayo/features/community_posts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pending = CommunityPost(
  routeName: 'Vigan City → Cabugao',
  from: 'Vigan City',
  to: 'Cabugao',
  vehicles: ['modern-jeepney'],
  hours: '',
  fare: 0,
  hubName: 'Vigan City',
  faresByVehicle: {'modern-jeepney': 60},
  operatorName: 'CTransco',
  status: PostStatus.pending,
);

const _approved = CommunityPost(
  routeName: 'Cabugao → Vigan City',
  from: 'Cabugao',
  to: 'Vigan City',
  vehicles: ['traditional-jeepney'],
  hours: '',
  fare: 0,
  hubName: 'Cabugao',
  faresByVehicle: {'traditional-jeepney': 60},
  status: PostStatus.approved,
);

const _rejected = CommunityPost(
  routeName: 'Sinait → Cabugao',
  from: 'Sinait',
  to: 'Cabugao',
  vehicles: ['tricycle'],
  hours: '',
  fare: 0,
  hubName: 'Cabugao',
  status: PostStatus.rejected,
);

void main() {
  testWidgets('admin screen states device-only review plainly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityAdminScreen(posts: const [_pending], onChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no server-side review'), findsOneWidget);
    expect(find.text('Pending verification'), findsOneWidget);
    expect(find.text('Vigan City → Cabugao'), findsOneWidget);
    expect(find.text('Operator: CTransco'), findsOneWidget);
  });

  testWidgets('admin approve moves a pending post to Published', (
    tester,
  ) async {
    List<CommunityPost>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityAdminScreen(
          posts: const [_pending],
          onChanged: (list) => changed = list,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed!.length, 1);
    expect(changed!.first.status, PostStatus.approved);
  });

  testWidgets('admin reject hides a pending post from the main list', (
    tester,
  ) async {
    List<CommunityPost>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityAdminScreen(
          posts: const [_pending],
          onChanged: (list) => changed = list,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed!.first.status, PostStatus.rejected);
    expect(showPostInCommunityList(changed!.first), isFalse);
  });

  testWidgets('admin sections show published and rejected posts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityAdminScreen(
          posts: const [_approved, _rejected],
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Cabugao → Vigan City'), findsOneWidget);
    expect(find.text('Sinait → Cabugao'), findsOneWidget);
  });

  testWidgets('admin delete asks for confirmation, then removes', (
    tester,
  ) async {
    List<CommunityPost>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityAdminScreen(
          posts: const [_rejected],
          onChanged: (list) => changed = list,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this post?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed, isEmpty);
  });
}
