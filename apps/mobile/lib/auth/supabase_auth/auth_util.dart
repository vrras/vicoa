import '/auth/builtin_auth/builtin_auth.dart';
import '/auth/builtin_auth/builtin_auth_manager.dart';
import '/backend/auth_mode.dart';
import '/backend/supabase/supabase.dart';
import '../base_auth_user_provider.dart';
import 'supabase_auth_manager.dart';
import 'supabase_user_provider.dart';

export 'supabase_auth_manager.dart';
export '/auth/builtin_auth/builtin_auth.dart' show AuthLifecycleEvent;

final _supabaseAuthManager = SupabaseAuthManager();
final _builtinAuthManager = BuiltinAuthManager();

// dynamic, not AuthManager: auth surfaces call mixin members
// (signInWithEmail, signInWithGoogle, updatePassword) that live on the
// concrete managers. In builtin mode the social members are never invoked —
// their buttons are hidden — but the same call sites must still compile.
dynamic get authManager =>
    kUseSupabaseAuth ? _supabaseAuthManager : _builtinAuthManager;

String get currentUserEmail => currentUser?.email ?? '';

String get currentUserUid => currentUser?.uid ?? '';

String get currentUserDisplayName => currentUser?.displayName ?? '';

String get currentUserPhoto => currentUser?.photoUrl ?? '';

String get currentPhoneNumber => currentUser?.phoneNumber ?? '';

String get currentJwtToken => kUseSupabaseAuth
    ? (_currentJwtToken ?? '')
    : (BuiltinAuth.instance.validToken ?? '');

bool get currentUserEmailVerified => currentUser?.emailVerified ?? false;

/// The current user's JWT Token. Kept updated by [jwtTokenStream] in supabase
/// mode; read straight off the builtin session otherwise.
String? _currentJwtToken;

/// A getter, not a top-level final: a final initializer would evaluate
/// `SupaFlow.client` at import time and crash builtin-mode startup, where
/// Supabase is never configured.
Stream<String?> get jwtTokenStream => kUseSupabaseAuth
    ? SupaFlow.client.auth.onAuthStateChange
        .map(
          (authState) => _currentJwtToken = authState.session?.accessToken,
        )
        .asBroadcastStream()
    : const Stream<String?>.empty();

/// The active user stream for the router gate — supabase auth changes in
/// hosted builds, the builtin session stream in self-hosted ones.
Stream<BaseAuthUser> authUserStream() => kUseSupabaseAuth
    ? vicoaSupabaseUserStream()
    : BuiltinAuth.instance.userStream;

/// Auth lifecycle reduced to what connection managers care about (sign-in /
/// sign-out). Supabase's richer AuthChangeEvent set maps onto it: every event
/// except signedOut means a usable token now exists. Also a getter for the
/// same reason as [jwtTokenStream].
Stream<AuthLifecycleEvent> get authLifecycleEvents => kUseSupabaseAuth
    ? SupaFlow.client.auth.onAuthStateChange
        .map((authState) => authState.event == AuthChangeEvent.signedOut
            ? AuthLifecycleEvent.signedOut
            : AuthLifecycleEvent.signedIn)
        .asBroadcastStream()
    : BuiltinAuth.instance.lifecycleEvents;
