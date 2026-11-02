// Shared fakes for the onboarding/auth/account tests.
//
// No real Firebase, no real permission dialogs: FakeAuthService keeps an
// in-memory user registry (email -> password, verified flag, display
// name) and FakePermissionService keeps an in-memory notification
// status. Both implement the production interfaces exactly, so the
// screens under test exercise their real code paths.
import 'dart:async';

import 'package:estudyantego/features/community_post_repository.dart';
import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:estudyantego/features/onboarding/permission_service.dart';

class _Record {
  _Record(this.password, this.displayName, this.verified);
  String password;
  String displayName;
  bool verified;
}

class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? user, this.configured = true}) {
    if (user != null) {
      _user = user;
      _records[user.email] =
          _Record('', user.displayName ?? '', user.emailVerified);
    }
  }

  final bool configured;

  @override
  bool get isConfigured => configured;

  AuthUser? _user;
  final Map<String, _Record> _records = {};
  final List<String> resetEmailsSent = [];
  bool verificationEmailSent = false;
  int signOutCount = 0;

  /// Google stub: the user a Google tap returns (null = unset).
  AuthUser? googleUser;

  /// When true, Google taps behave as user-canceled (return null).
  bool googleCanceled = false;
  int googleSignInCount = 0;
  int googleSignUpCount = 0;

  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void _checkConfigured() {
    if (!configured) throw const AuthNotConfiguredException();
  }

  /// Marks the current user verified, as if they clicked the email link.
  void markCurrentUserVerified() {
    final user = _user;
    if (user == null) return;
    _user = user.copyWith(emailVerified: true);
    _records[user.email]?.verified = true;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _checkConfigured();
    final record = _records[email];
    if (record == null || record.password != password) {
      throw const AuthException('Incorrect email or password.');
    }
    _user = AuthUser(
      uid: 'uid-${email.hashCode}',
      email: email,
      displayName: record.displayName,
      emailVerified: record.verified,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _checkConfigured();
    if (_records.containsKey(email)) {
      throw const AuthException('That email is already registered.');
    }
    _records[email] = _Record(password, displayName, false);
    _user = AuthUser(
      uid: 'uid-${email.hashCode}',
      email: email,
      displayName: displayName,
      emailVerified: false,
    );
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    _checkConfigured();
    resetEmailsSent.add(email);
  }

  @override
  Future<void> sendEmailVerification() async {
    _checkConfigured();
    if (_user == null) {
      throw const AuthException('No account signed in.');
    }
    verificationEmailSent = true;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    _checkConfigured();
    return _user;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    _checkConfigured();
    googleSignInCount++;
    if (googleCanceled) return null;
    final user = googleUser;
    if (user == null) return null;
    _user = user;
    _controller.add(_user);
    return user;
  }

  @override
  Future<AuthUser?> signUpWithGoogle() async {
    _checkConfigured();
    googleSignUpCount++;
    if (googleCanceled) return null;
    final user = googleUser;
    if (user == null) return null;
    _user = user;
    _controller.add(_user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _checkConfigured();
    _user = null;
    signOutCount++;
    _controller.add(null);
  }
}

class FakePermissionService implements PermissionService {
  FakePermissionService({
    NotificationPermissionStatus initial =
        NotificationPermissionStatus.denied,
    this.requestResult = NotificationPermissionStatus.granted,
  }) : _status = initial;

  NotificationPermissionStatus _status;
  final NotificationPermissionStatus requestResult;
  int requestCount = 0;
  int settingsOpenedCount = 0;

  @override
  Future<NotificationPermissionStatus> notificationStatus() async =>
      _status;

  @override
  Future<NotificationPermissionStatus> requestNotification() async {
    requestCount++;
    _status = requestResult;
    return _status;
  }

  @override
  Future<void> openAppSettings() async {
    settingsOpenedCount++;
  }
}

/// In-memory [PostRepository] mirroring the Firestore visibility rule
/// (see [sharedPostVisibleTo]) and the photo guard: a photo larger
/// than [kMaxSharedDocBytes] is dropped, never failed over.
class FakePostRepository implements PostRepository {
  final List<CommunityPost> stored = [];
  int _nextId = 1;

  /// When true, [createPost] throws, simulating a Firestore failure
  /// (e.g. database not created yet).
  bool failCreates = false;

  @override
  Future<List<CommunityPost>> loadVisiblePosts(AuthUser? user) async {
    final visible =
        stored.where((p) => sharedPostVisibleTo(p, user)).toList();
    visible.sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    return visible;
  }

  @override
  Future<SharedPostCreation> createPost(
    CommunityPost post,
    AuthUser author,
  ) async {
    if (failCreates) {
      throw Exception('Simulated Firestore failure.');
    }
    var photo = post.photoBase64;
    var photoDropped = false;
    if (photo != null && photo.length > kMaxSharedDocBytes) {
      photo = null;
      photoDropped = true;
    }
    final created = CommunityPost(
      routeName: post.routeName,
      vehicles: post.vehicles,
      hours: post.hours,
      fare: post.fare,
      hubName: post.hubName,
      from: post.from,
      to: post.to,
      photoBase64: photo,
      faresByVehicle: post.faresByVehicle,
      operatorName: post.operatorName,
      status: PostStatus.pending,
      id: 'fake-${_nextId++}',
      authorUid: author.uid,
      createdAt: DateTime.now(),
    );
    stored.add(created);
    return (post: created, photoDropped: photoDropped);
  }

  @override
  Future<void> updatePostStatus(
    CommunityPost post,
    PostStatus status, {
    String? rejectionReason,
    bool clearRejectionReason = false,
  }) async {
    final error = postStatusUpdateError(
      status: status,
      rejectionReason: rejectionReason,
      clearRejectionReason: clearRejectionReason,
    );
    if (error != null) throw ArgumentError(error);
    final index = stored.indexWhere((p) => p.id == post.id);
    if (index < 0) throw StateError('Post not found.');
    if (status == PostStatus.rejected) {
      final reason = rejectionReason?.trim();
      if (reason != null && reason.isNotEmpty) {
        stored[index] = stored[index].copyWith(
          status: status,
          rejectionReason: reason,
        );
      } else if (clearRejectionReason || rejectionReason != null) {
        stored[index] = stored[index].copyWith(
          status: status,
          clearRejectionReason: true,
        );
      } else {
        stored[index] = stored[index].copyWith(status: status);
      }
    } else {
      stored[index] = stored[index].copyWith(status: status);
    }
  }

  @override
  Future<void> deletePost(CommunityPost post) async {
    stored.removeWhere((p) => p.id == post.id);
  }
}
