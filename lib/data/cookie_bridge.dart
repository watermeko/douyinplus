import 'package:flutter/services.dart';

/// Reads HttpOnly cookies from Android's WebView CookieManager.
///
/// `document.cookie` cannot see HttpOnly cookies (including `sessionid`), so
/// the login page delegates to the native CookieManager through this channel.
class CookieBridge {
  static const MethodChannel _channel = MethodChannel(
    'dev.watermeko.douyinplus/cookies',
  );

  static Future<Map<String, String>> readDouyinCookies() async {
    try {
      final header = await _channel.invokeMethod<String>('getCookieHeader', {
        'url': 'https://www.douyin.com',
      });
      return parseCookieHeader(header ?? '');
    } on PlatformException {
      return <String, String>{};
    } on MissingPluginException {
      return <String, String>{};
    }
  }

  static Future<void> clearAll() async {
    try {
      await _channel.invokeMethod<void>('removeAllCookies');
    } catch (_) {
      // Best effort.
    }
  }

  /// Writes the saved session cookies into the shared WebView CookieManager.
  ///
  /// Used to keep the hidden signature WebView in sync when the session was
  /// imported from a debug file rather than created by the login WebView.
  /// Returns false when the native side is unavailable.
  static Future<bool> setDouyinCookies(Map<String, String> cookies) async {
    if (cookies.isEmpty) return true;
    try {
      final result = await _channel.invokeMethod<bool>('setCookies', {
        'url': 'https://www.douyin.com',
        'cookies': cookies,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Map<String, String> parseCookieHeader(String header) {
    final result = <String, String>{};
    for (final part in header.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isNotEmpty) result[name] = value;
    }
    return result;
  }
}
