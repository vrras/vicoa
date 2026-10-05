import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/auth_mode.dart';
import '../base_auth_user_provider.dart';

/// Why the session ended up signed out (or in) — the subset of Supabase's
/// AuthChangeEvent that builtin auth can actually produce. There is no
/// tokenRefreshed: builtin JWTs are not refreshed; expiry means sign-in again.
enum AuthLifecycleEvent { signedIn, signedOut }

/// Error surfaced from the builtin auth endpoints; [message] is the backend's
/// `detail` string (e.g. "Wrong email or password") for direct display.
class BuiltinAuthException implements Exception {
  BuiltinAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A signed-in builtin user, shaped like the backend's SessionUser. A null
/// [user] is the logged-out placeholder (mirrors VicoaSupabaseUser(null)).
class BuiltinAuthUser extends BaseAuthUser {
  BuiltinAuthUser(this.user);
  final Map<String, dynamic>? user;

  @override
  bool get loggedIn => user != null;

  @override
  bool get emailVerified => true;

  @override
  AuthUserInfo get authUserInfo => AuthUserInfo(
        uid: user?['id'] as String?,
        email: user?['email'] as String?,
        displayName: user?['display_name'] as String?,
      );

  @override
  Future? delete() =>
      throw UnsupportedError('Account deletion is not supported on this build.');

  @override
  Future? updateEmail(String email) => throw UnsupportedError(
      'Email changes are not supported on this build.');

  @override
  Future? updatePassword(String newPassword) =>
      BuiltinAuth.instance.changePassword(currentPassword: null, newPassword: newPassword);

  @override
  Future? sendEmailVerification() => throw UnsupportedError(
      'Email verification is not supported on this build.');

  @override
  Future refreshUser() async {}
}

/// Self-hosted session store + signer: the mobile counterpart of the web
/// app's `builtin-client.ts`. One SharedPreferences key holds the whole
/// session (`{access_token, expires_at, user}`); the token is a backend-minted
/// RS256 JWT that the client decodes (without verifying) only to check `exp`.
class BuiltinAuth {
  BuiltinAuth._();
  static final BuiltinAuth instance = BuiltinAuth._();

  static const _storageKey = 'vicoa_builtin_session';

  final _userController = StreamController<BaseAuthUser>.broadcast();
  final _lifecycleController =
      StreamController<AuthLifecycleEvent>.broadcast();

  Map<String, dynamic>? _session;

  /// Restore a persisted session at startup, before the router builds. An
  /// expired session is dropped so the router resolves to sign-in directly.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_storageKey);
        return;
      }
      _session = decoded;
      if (validToken == null) {
        _session = null;
        await prefs.remove(_storageKey);
        return;
      }
      debugPrint('[auth] builtin session restored');
    } catch (e) {
      debugPrint('[auth] builtin session restore failed: $e');
      _session = null;
    }
  }

  /// The current JWT, or null when signed out or expired. Callers re-auth by
  /// getting null; the backend is the only verifier.
  String? get validToken {
    final session = _session;
    if (session == null) return null;
    final token = session['access_token'] as String?;
    if (token == null || token.isEmpty) return null;
    final claims = _decodeJwtPayload(token);
    final exp = claims?['exp'];
    if (exp is! num) return null;
    if (DateTime.now().millisecondsSinceEpoch / 1000 >= exp) return null;
    return token;
  }

  /// The signed-in user, or null. Reads the stored session user, not the JWT
  /// claims, so display name survives even while offline.
  Map<String, dynamic>? get currentUser => _session?['user'] as Map<String, dynamic>?;

  /// Emits the initial state immediately (logged-out when no session), then
  /// every change — mirrors vicoaSupabaseUserStream's seed-first contract so
  /// the router gate resolves without waiting for network.
  Stream<BaseAuthUser> get userStream async* {
    yield BuiltinAuthUser(currentUser);
    yield* _userController.stream;
  }

  Stream<AuthLifecycleEvent> get lifecycleEvents => _lifecycleController.stream;

  Future<BuiltinAuthUser> signIn(String email, String password) =>
      _authenticate('sign-in', email, password);

  Future<BuiltinAuthUser> signUp(String email, String password) =>
      _authenticate('sign-up', email, password);

  Future<BuiltinAuthUser> _authenticate(
    String action,
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$kVicoaApiUrl/api/v1/auth/builtin/$action'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BuiltinAuthException(_errorMessage(response));
    }
    final session = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    await _setSession(session);
    return BuiltinAuthUser(session['user'] as Map<String, dynamic>?);
  }

  /// Requires an existing (valid) session; returns false on wrong password.
  Future<bool> changePassword({
    required String? currentPassword,
    required String newPassword,
  }) async {
    final token = validToken;
    if (token == null) {
      throw BuiltinAuthException('Not signed in');
    }
    final response = await http.post(
      Uri.parse('$kVicoaApiUrl/api/v1/auth/builtin/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'current_password': currentPassword ?? '',
        'new_password': newPassword,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BuiltinAuthException(_errorMessage(response));
    }
    return true;
  }

  /// POSTs the reset code email. Always 2xx from the backend (no account
  /// enumeration); only network/parse failures throw here.
  Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$kVicoaApiUrl/api/v1/auth/builtin/forgot-password'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BuiltinAuthException(_errorMessage(response));
    }
  }

  Future<void> signOut() async {
    _session = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('[auth] builtin session clear failed: $e');
    }
    _userController.add(BuiltinAuthUser(null));
    _lifecycleController.add(AuthLifecycleEvent.signedOut);
  }

  Future<void> _setSession(Map<String, dynamic> session) async {
    _session = session;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(session));
    } catch (e) {
      debugPrint('[auth] builtin session persist failed: $e');
    }
    _userController.add(BuiltinAuthUser(session['user'] as Map<String, dynamic>?));
    _lifecycleController.add(AuthLifecycleEvent.signedIn);
  }

  static Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Test hook: clears in-memory state so each test seeds a fresh store.
  @visibleForTesting
  void resetForTest() {
    _session = null;
  }

  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
      }
    } catch (_) {}
    return 'Authentication failed (${response.statusCode})';
  }
}
