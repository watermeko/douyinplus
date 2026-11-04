import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Douyin web session cookies encrypted at rest.
///
/// The cookie set is kept as a JSON object in a single secure-storage entry.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'douyin_cookies_v1';

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> loadCookies() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            if (entry.key.toString().isNotEmpty)
              entry.key.toString(): entry.value?.toString() ?? '',
        };
      }
    } catch (_) {
      // Corrupt storage or unavailable keystore: treat as logged out.
    }
    return <String, String>{};
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    final normalized = <String, String>{
      for (final entry in cookies.entries)
        if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value,
    };
    await _storage.write(key: _storageKey, value: jsonEncode(normalized));
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {
      // Best effort: local session is discarded even if the keystore fails.
    }
  }

  Future<bool> hasSession() async {
    final cookies = await loadCookies();
    return (cookies['sessionid'] ?? '').isNotEmpty;
  }

  Future<String?> cookieHeader() async {
    final cookies = await loadCookies();
    if (cookies.isEmpty) return null;
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<String?> valueOf(String name) async {
    final cookies = await loadCookies();
    return cookies[name];
  }
}
