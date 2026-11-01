// Copy + share for the real on-device friend code, behind an
// interface so tests use a fake and production uses the real
// clipboard + share sheet.
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

abstract class FriendSharing {
  Future<void> copyCode(String code);
  Future<void> shareCode(String code);
}

class SystemFriendSharing implements FriendSharing {
  @override
  Future<void> copyCode(String code) =>
      Clipboard.setData(ClipboardData(text: code));

  @override
  Future<void> shareCode(String code) => SharePlus.instance.share(
        ShareParams(text: 'My EstudyanteGO friend code: $code'),
      );
}
