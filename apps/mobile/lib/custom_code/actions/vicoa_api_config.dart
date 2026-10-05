// Automatic FlutterFlow imports
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '/backend/auth_mode.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

/// Returns the base URL for the Vicoa backend API based on build mode.
///
/// - Debug mode: Uses local backend (Android emulator uses 10.0.2.2, others use localhost)
/// - Release mode: Always uses production URL (https://api.vicoa.ai)
String getVicoaApiBaseUrl() {
  // Self-hosted build: the backend URL comes from env.json, not the hosted
  // default below.
  if (kVicoaApiUrl.isNotEmpty) {
    return kVicoaApiUrl;
  }
  if (kDebugMode) {
    // Android emulator routes 10.0.2.2 to the host machine's localhost
    final host = !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';
    // return 'http://$host:8000';
    return 'https://api.vicoa.ai';
  }

  return 'https://api.vicoa.ai';
}

/// Returns the `/ws` WebSocket endpoint URL (websocket-migration plan §2.1).
///
/// The endpoint lives on the agent-facing `server` process, served on port 443
/// under the canonical hostname `agents.vicoa.ai` — a different host than the
/// REST base URL above.
String getVicoaWsUrl() {
  // Self-hosted build override (see getVicoaApiBaseUrl).
  if (kVicoaWsUrl.isNotEmpty) {
    return kVicoaWsUrl;
  }
  if (kDebugMode) {
    // Android emulator routes 10.0.2.2 to the host machine's localhost.
    final host = !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';
    // return 'ws://$host:8080/ws';
    return 'wss://agents.vicoa.ai/ws';
  }

  return 'wss://agents.vicoa.ai/ws';
}
