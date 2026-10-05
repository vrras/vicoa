// Automatic FlutterFlow imports
import '/backend/auth_mode.dart';
import '/backend/supabase/supabase.dart';
import 'index.dart';
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

Future<dynamic> apiGetMobileSubscriptionStatus() async {
  // Hosted billing endpoint; self-host has no subscriptions.
  if (!kUseSupabaseAuth) return null;
  try {
    final result = await vicoaApiRequest('get', '/api/v1/billing/mobile/status', null);
    return result;
  } on AuthenticationException {
    rethrow;
  } on NetworkException {
    rethrow;
  } catch (e) {
    debugPrint('Error getting mobile subscription status: $e');
    return null;
  }
}
