import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vicoa/auth/base_auth_user_provider.dart';
import 'package:vicoa/auth/builtin_auth/builtin_auth.dart';

/// Builds a syntactically valid RS256-shaped JWT (the client only ever
/// decodes the payload; the signature is never verified client-side).
String makeJwt({required DateTime expiresAt}) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'RS256'})}.${b64({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, dynamic> sessionFor(String token) => {
      'access_token': token,
      'expires_at': '2099-01-01T00:00:00Z',
      'user': {'id': 'u1', 'email': 'a@b.c', 'display_name': 'Fir'},
    };

Future<void> seedSession(Map<String, dynamic>? session) async {
  SharedPreferences.setMockInitialValues({
    if (session != null) 'vicoa_builtin_session': jsonEncode(session),
  });
  BuiltinAuth.instance.resetForTest();
  await BuiltinAuth.instance.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('validToken is null with no stored session', () async {
    await seedSession(null);
    expect(BuiltinAuth.instance.validToken, isNull);
    expect(BuiltinAuth.instance.currentUser, isNull);
  });

  test('validToken survives a restart while unexpired, drops when expired',
      () async {
    final token =
        makeJwt(expiresAt: DateTime.now().add(const Duration(hours: 1)));
    await seedSession(sessionFor(token));
    expect(BuiltinAuth.instance.validToken, token);
    expect(BuiltinAuth.instance.currentUser?['id'], 'u1');

    final expired =
        makeJwt(expiresAt: DateTime.now().subtract(const Duration(minutes: 5)));
    await seedSession(sessionFor(expired));
    // An expired persisted session is dropped at load, not handed out — the
    // router must land on sign-in, not on a 401 loop.
    expect(BuiltinAuth.instance.validToken, isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString('vicoa_builtin_session'),
        isNull);
  });

  test('userStream seeds the current state before yielding changes', () async {
    final token =
        makeJwt(expiresAt: DateTime.now().add(const Duration(hours: 1)));
    await seedSession(sessionFor(token));

    final first = await BuiltinAuth.instance.userStream.first;
    expect(first.loggedIn, isTrue);
    expect(first.uid, 'u1');
    expect(first.displayName, 'Fir');
    expect(first.emailVerified, isTrue);
  });

  test('signOut clears the session and emits logged-out + signedOut', () async {
    final token =
        makeJwt(expiresAt: DateTime.now().add(const Duration(hours: 1)));
    await seedSession(sessionFor(token));

    final lifecycle = <AuthLifecycleEvent>[];
    final sub = BuiltinAuth.instance.lifecycleEvents.listen(lifecycle.add);
    final users = <BaseAuthUser>[];
    final userSub = BuiltinAuth.instance.userStream.listen(users.add);

    await BuiltinAuth.instance.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(BuiltinAuth.instance.validToken, isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString('vicoa_builtin_session'),
        isNull);
    expect(lifecycle, [AuthLifecycleEvent.signedOut]);
    expect(users.whereType<BuiltinAuthUser>().last.loggedIn, isFalse);

    await sub.cancel();
    await userSub.cancel();
  });
}
