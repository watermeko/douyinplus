import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cookie_bridge.dart';
import 'douyin_api.dart';
import 'models/user_profile.dart';
import 'session_store.dart';

enum AuthStatus { checking, loggedOut, loggedIn, error }

class AppController extends ChangeNotifier {
  AppController({SessionStore? sessionStore})
    : sessionStore = sessionStore ?? SessionStore() {
    api = DouyinApi(this.sessionStore);
  }

  final SessionStore sessionStore;
  late final DouyinApi api;

  AuthStatus status = AuthStatus.checking;
  UserProfile? profile;
  String? error;
  bool isRefreshing = false;

  Future<void> bootstrap() async {
    status = AuthStatus.checking;
    notifyListeners();

    if (kDebugMode) {
      await _importDebugCookiesIfNeeded();
    }

    if (!await sessionStore.hasSession()) {
      status = AuthStatus.loggedOut;
      error = null;
      notifyListeners();
      return;
    }

    await refreshProfile();
  }

  Future<void> refreshProfile({bool silent = false}) async {
    if (isRefreshing) return;
    isRefreshing = true;
    if (!silent) {
      status = AuthStatus.checking;
      notifyListeners();
    }

    try {
      final nextProfile = await api.fetchSelfProfile();
      profile = nextProfile;
      status = AuthStatus.loggedIn;
      error = null;
    } catch (exception) {
      error = api.describeError(exception);
      final isAuthError =
          exception is DouyinApiException && exception.isAuthError;
      if (isAuthError) {
        status = AuthStatus.loggedOut;
      } else if (profile != null) {
        status = AuthStatus.loggedIn;
      } else {
        status = AuthStatus.error;
      }
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> completeLogin(Map<String, String> cookies) async {
    try {
      await sessionStore.saveCookies(cookies);
    } catch (exception) {
      error = '无法保存登录信息：$exception';
      status = AuthStatus.error;
      notifyListeners();
      return;
    }
    profile = null;
    status = AuthStatus.checking;
    error = null;
    notifyListeners();
    await refreshProfile(silent: true);
  }

  Future<bool> importCookies(Map<String, String> cookies) async {
    if ((cookies['sessionid'] ?? '').isEmpty) {
      error = '缺少 sessionid，无法登录';
      notifyListeners();
      return false;
    }
    await completeLogin(cookies);
    return status == AuthStatus.loggedIn;
  }

  Future<bool> importDebugCookieFile() async {
    final file = await _findDebugCookieFile();
    if (file == null) {
      error = '未找到调试 cookie 文件';
      notifyListeners();
      return false;
    }
    final cookies = await _readCookieFile(file);
    if (cookies.isEmpty) {
      error = '调试 cookie 文件格式无效';
      notifyListeners();
      return false;
    }
    return importCookies(cookies);
  }

  Future<void> logout() async {
    await sessionStore.clear();
    await CookieBridge.clearAll();
    profile = null;
    error = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _importDebugCookiesIfNeeded() async {
    if (await sessionStore.hasSession()) return;
    final file = await _findDebugCookieFile();
    if (file == null) return;
    final cookies = await _readCookieFile(file);
    if ((cookies['sessionid'] ?? '').isEmpty) return;
    await sessionStore.saveCookies(cookies);
    debugPrint('Dev cookies imported from ${file.path}');
  }

  Future<File?> _findDebugCookieFile() async {
    final candidates = <Directory>[];
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) candidates.add(external);
    } catch (_) {}
    try {
      candidates.add(await getApplicationDocumentsDirectory());
    } catch (_) {}
    for (final directory in candidates) {
      final file = File('${directory.path}/douyin_cookies.json');
      if (await file.exists()) return file;
    }
    return null;
  }

  Future<Map<String, String>> _readCookieFile(File file) async {
    try {
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return {};
      return parseCookieInput(raw);
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> parseCookieInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return {};
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return {
            for (final entry in decoded.entries)
              if (entry.key.toString().trim().isNotEmpty)
                entry.key.toString().trim(): entry.value?.toString() ?? '',
          };
        }
      } on FormatException {
        return {};
      }
    }
    final result = <String, String>{};
    for (final part in text.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isNotEmpty) result[name] = value;
    }
    return result;
  }
}
