import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AppErrorMapper {
  static String toMessage(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is AuthException) {
      return _clean(error.message, fallback: fallback);
    }

    if (error is PostgrestException) {
      return _clean(error.message, fallback: fallback);
    }

    final raw = error.toString();
    final normalized = raw.toLowerCase();

    if (normalized.contains('failed host lookup') ||
        normalized.contains('socketexception') ||
        normalized.contains('clientexception') ||
        normalized.contains('xmlhttprequest error') ||
        normalized
            .contains('connection closed before full header was received')) {
      final host = Uri.tryParse(SupabaseConfig.url)?.host ?? SupabaseConfig.url;
      return 'Unable to reach the server ($host). Check internet, SUPABASE_URL, and Android INTERNET permission.';
    }

    if (normalized.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }

    return _clean(raw, fallback: fallback);
  }

  static String _clean(
    String value, {
    required String fallback,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;

    const prefixes = <String>[
      'Exception: ',
      'AuthException(message: ',
      'PostgrestException(message: ',
    ];

    for (final prefix in prefixes) {
      if (trimmed.startsWith(prefix)) {
        var cleaned = trimmed.substring(prefix.length).trim();
        if (cleaned.endsWith(')')) {
          cleaned = cleaned.substring(0, cleaned.length - 1).trim();
        }
        return cleaned;
      }
    }

    return trimmed;
  }
}
