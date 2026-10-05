import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:superwallkit_flutter/superwallkit_flutter.dart';

import '/auth/auth_manager.dart';
import '/flutter_flow/nav/nav.dart';
import '/pages/snack_bar/snack_bar_widget.dart';

import '../base_auth_user_provider.dart';
import 'builtin_auth.dart';

export '/auth/base_auth_user_provider.dart';
export 'builtin_auth.dart' show BuiltinAuthUser;

/// Email-password auth against the self-hosted backend's builtin endpoints.
/// Drop-in counterpart of SupabaseAuthManager for the subset of mixins the
/// app actually uses in builtin mode (EmailSignInManager only — social
/// buttons are hidden in that mode).
class BuiltinAuthManager extends AuthManager with EmailSignInManager {
  static final BuiltinAuthManager _instance = BuiltinAuthManager._();
  factory BuiltinAuthManager() => _instance;
  BuiltinAuthManager._();

  BuiltinAuth get _auth => BuiltinAuth.instance;

  @override
  Future<BaseAuthUser?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) =>
      _signInOrCreateAccount(context, () => _auth.signIn(email, password));

  @override
  Future<BaseAuthUser?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) =>
      _signInOrCreateAccount(context, () => _auth.signUp(email, password));

  /// Mirrors SupabaseAuthManager._signInOrCreateAccount: assign [currentUser]
  /// eagerly so post-sign-in code reading the global doesn't race the stream.
  Future<BaseAuthUser?> _signInOrCreateAccount(
    BuildContext context,
    Future<BuiltinAuthUser> Function() authFunc,
  ) async {
    try {
      final authUser = await authFunc();
      currentUser = authUser;
      AppStateNotifier.instance.update(authUser);
      return authUser;
    } on BuiltinAuthException catch (e) {
      await _showSnackBarSheet(context, e.message);
      return null;
    } catch (e) {
      debugPrint('Builtin sign-in failed: $e');
      await _showSnackBarSheet(context, 'Could not sign in. Check your connection and try again.');
      return null;
    }
  }

  @override
  Future signOut() async {
    // Same billing-identity reset as SupabaseAuthManager: the next account on
    // this device must not inherit the previous user's revenue ids.
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('Purchases.logOut failed: $e');
    }
    try {
      await Superwall.shared.reset();
    } catch (e) {
      debugPrint('Superwall.reset failed: $e');
    }
    await _auth.signOut();
  }

  @override
  Future deleteUser(BuildContext context) async =>
      throw UnsupportedError('Account deletion is not supported on this build.');

  @override
  Future updateEmail({
    required String email,
    required BuildContext context,
  }) async =>
      throw UnsupportedError('Email changes are not supported on this build.');

  @override
  Future updatePassword({
    required String newPassword,
    required BuildContext context,
  }) async {
    try {
      await _auth.changePassword(currentPassword: null, newPassword: newPassword);
    } on BuiltinAuthException catch (e) {
      await _showSnackBarSheet(context, e.message);
      return;
    }
    await _showSnackBarSheet(context, 'Password updated successfully');
  }

  @override
  Future resetPassword({
    required String email,
    required BuildContext context,
    String? redirectTo,
  }) async {
    try {
      await _auth.forgotPassword(email);
    } on BuiltinAuthException catch (e) {
      await _showSnackBarSheet(context, e.message);
      return;
    }
    await _showSnackBarSheet(context, 'Password reset email sent');
  }

  Future<void> _showSnackBarSheet(BuildContext context, String content) async {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold == null) {
      return;
    }
    scaffold.showBottomSheet(
      (context) {
        return Align(
          alignment: AlignmentDirectional(0.0, 1.0)
              .resolve(Directionality.of(context)),
          child: SnackBarWidget(
            content: content,
            waitTime: 2200,
          ),
        );
      },
      backgroundColor: Colors.transparent,
      enableDrag: false,
    );
  }
}
