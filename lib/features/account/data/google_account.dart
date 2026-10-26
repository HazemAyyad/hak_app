import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class HaqGoogleAccount {
  static const serverId = String.fromEnvironment('HAQ_GOOGLE_WEB_CLIENT_ID');
  static const iosId = String.fromEnvironment('HAQ_GOOGLE_IOS_CLIENT_ID');
  static bool get configured =>
      !kIsWeb &&
      serverId.isNotEmpty &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS && iosId.isNotEmpty);
  static Future<void>? _initializing;
  static Future<String?> token({bool fresh = false}) async {
    if (!configured) throw StateError('Google is not configured');
    final google = GoogleSignIn.instance;
    try {
      await (_initializing ??= google.initialize(
        serverClientId: serverId,
        clientId: defaultTargetPlatform == TargetPlatform.iOS ? iosId : null,
      ));
    } catch (_) {
      _initializing = null;
      rethrow;
    }
    if (fresh) await google.signOut();
    try {
      final account = await google.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
