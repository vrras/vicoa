// Build-time auth-mode switch, mirroring the web app's provider split
// (apps/web/lib/auth/auth-provider.ts). One source tree builds both apps:
//
//  - Hosted build: `--dart-define-from-file=env.json` carries SUPABASE_URL (+
//    SUPABASE_ANON_KEY, consumed by backend/supabase/supabase.dart) — Supabase
//    auth, exactly as today.
//  - Self-hosted build: env.json omits SUPABASE_URL and carries VICOA_API_URL
//    (+ VICOA_WS_URL) instead — builtin auth against the self-hosted backend
//    (`/api/v1/auth/builtin/*`). See lib/auth/builtin_auth/builtin_auth.dart.
//
// All consts are compile-time, so tree-shaking drops the Supabase-only code
// paths from self-hosted binaries and vice versa.
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Whether this build authenticates against Supabase (hosted) or the
/// self-hosted backend's builtin auth. `final`, not `const` — `.isNotEmpty`
/// isn't a const expression in Dart — so all mode checks are runtime checks
/// on a value fixed at startup. Every Supabase touch stays behind it.
final kUseSupabaseAuth = kSupabaseUrl.isNotEmpty;

/// Self-hosted backend REST base URL (e.g. https://api-vicoa.example.com).
const kVicoaApiUrl = String.fromEnvironment('VICOA_API_URL');

/// Self-hosted agent-server WS endpoint (e.g. wss://agents.example.com/ws).
const kVicoaWsUrl = String.fromEnvironment('VICOA_WS_URL');
