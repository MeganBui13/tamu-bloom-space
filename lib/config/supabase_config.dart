import 'dart:async';

import 'package:http/http.dart' as http;

class SupabaseConfig {
  static const String _defaultUrl = 'https://emmrljybzwllxoiatfiy.supabase.co';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtbXJsanliendsbHhvaWF0Zml5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5ODc2NjgsImV4cCI6MjA3OTU2MzY2OH0.blUDDD1jRzsowcdaSX8dqLMu044vrwiZEY3yDxTS9J8';

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultUrl,
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultAnonKey,
  );

  static String? validate() {
    if (url.trim().isEmpty) {
      return 'Missing Supabase URL. Set SUPABASE_URL with --dart-define.';
    }

    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || !parsedUrl.hasScheme || parsedUrl.host.isEmpty) {
      return 'Invalid SUPABASE_URL: $url';
    }

    if (parsedUrl.scheme != 'https') {
      return 'SUPABASE_URL must use https.';
    }

    final key = anonKey.trim();
    if (key.isEmpty) {
      return 'Missing SUPABASE_ANON_KEY.';
    }

    final isPublishable = key.startsWith('sb_publishable_');
    final isLegacyJwt = key.split('.').length == 3;
    final isSecret = key.startsWith('sb_secret_');

    if (isSecret) {
      return 'SUPABASE_ANON_KEY must be a publishable/anon key, not sb_secret_...';
    }

    if (!isPublishable && !isLegacyJwt) {
      return 'Invalid SUPABASE_ANON_KEY. Use sb_publishable_... or legacy anon JWT.';
    }

    if (parsedUrl.host == 'emmrljybzwllxoiatfiy.supabase.co') {
      return 'Supabase host "emmrljybzwllxoiatfiy.supabase.co" does not resolve. '
          'Use your active project URL in SUPABASE_URL.';
    }

    return null;
  }

  static Future<String?> verifyReachability() async {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || parsedUrl.host.isEmpty) {
      return 'Invalid SUPABASE_URL: $url';
    }

    final healthUri = parsedUrl.replace(path: '/auth/v1/health', query: '');

    try {
      final response = await http.get(
        healthUri,
        headers: {'apikey': anonKey},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 500) {
        return 'Supabase is reachable but unhealthy (HTTP ${response.statusCode}).';
      }
    } on TimeoutException {
      return 'Timed out reaching Supabase host "${parsedUrl.host}".';
    } catch (error) {
      final raw = error.toString().toLowerCase();
      if (raw.contains('failed host lookup') ||
          raw.contains('socketexception') ||
          raw.contains('clientexception') ||
          raw.contains('xmlhttprequest error')) {
        return 'Supabase host "${parsedUrl.host}" is unreachable. Verify SUPABASE_URL and your network.';
      }

      return 'Could not reach Supabase host "${parsedUrl.host}": ${error.toString()}';
    }

    return null;
  }
}
