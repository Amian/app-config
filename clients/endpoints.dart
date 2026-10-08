// endpoints.dart — reference copy lives in github.com/Amian/app-config (clients/).
// Copy this file into the app unchanged (needs shared_preferences). It reads the app's backend
// addresses from the shared endpoints file, so a backend can move without an app update.
//
// Launch never waits for the network: it uses the copy saved last time, else the built-in
// defaults, then fetches the file in the background (Cloudflare first, GitHub as backup).
// A file that fails any check is ignored and the saved copy is kept.
//
// Usage (once, in main() before runApp; it only awaits local storage):
//     await Endpoints.configure(appId: 'com.amian.antiqueidentifier', defaults: {
//       'api': 'https://backend-j5mh.onrender.com',
//     });
// Then build requests from `Endpoints.url('api')`, and on a network error or 5xx call
// `Endpoints.refresh()` (throttled to once a minute) so a moved backend is picked up at once.
// Use the same appId on iOS and Android (the iOS bundle ID), whatever the Android package is.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class Endpoints {
  Endpoints._();

  static List<Uri> sources = [
    Uri.parse('https://apptor-config.pages.dev/endpoints.json'),
    Uri.parse('https://raw.githubusercontent.com/Amian/app-config/main/public/endpoints.json'),
  ];

  static const _cacheKey = 'endpoints.v1';
  static const _timeout = Duration(seconds: 5);
  static String _appId = '';
  static Map<String, Uri> _builtIn = {};
  static Map<String, Uri> _current = {};
  static bool _refreshing = false;
  static DateTime? _lastRefresh;

  /// Call once at launch. `defaults` must name every service the app uses.
  static Future<void> configure({
    required String appId,
    required Map<String, String> defaults,
  }) async {
    _appId = appId;
    _builtIn = defaults.map((name, value) => MapEntry(name, Uri.parse(value)));
    _current = Map.of(_builtIn);
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (saved != null) {
        final services = (jsonDecode(saved) as Map).cast<String, String>();
        _current.addAll(services.map((name, value) => MapEntry(name, Uri.parse(value))));
      }
    } catch (_) {
      // A broken saved copy is ignored; the built-in defaults stand.
    }
    unawaited(refresh(force: true));
  }

  /// The base address for a service, e.g. `Endpoints.url('api')`.
  static Uri url(String name) {
    final url = _current[name] ?? _builtIn[name];
    if (url == null) {
      throw StateError('Endpoints: no address for "$name". Add it to the defaults in configure().');
    }
    return url;
  }

  /// Fetches the file again. Throttled to once a minute unless `force` is set.
  static Future<void> refresh({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastRefresh;
    if (_refreshing || (!force && last != null && now.difference(last) < const Duration(minutes: 1))) {
      return;
    }
    _refreshing = true;
    _lastRefresh = now;
    try {
      for (final source in sources) {
        final services = await _fetch(source);
        if (services == null) continue;
        _current = {
          ..._builtIn,
          ...services.map((name, value) => MapEntry(name, Uri.parse(value))),
        };
        try {
          await (await SharedPreferences.getInstance()).setString(_cacheKey, jsonEncode(services));
        } catch (_) {
          // Saving is best effort; the new addresses are already in use.
        }
        return;
      }
    } finally {
      _refreshing = false;
    }
  }

  /// The services for this app (shared defaults plus its own entry), or null if the file fails
  /// any check. Every address must be https.
  static Future<Map<String, String>?> _fetch(Uri source) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(source).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final file = jsonDecode(body);
      if (file is! Map || file['version'] != 1) return null;

      final apps = file['apps'];
      final services = <String, String>{};
      for (final section in [file['default'], apps is Map ? apps[_appId] : null]) {
        if (section == null) continue;
        if (section is! Map) return null;
        for (final entry in section.entries) {
          final name = entry.key;
          final value = entry.value;
          final uri = value is String ? Uri.tryParse(value) : null;
          if (name is! String || uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
            return null;
          }
          services[name] = value as String;
        }
      }
      return services;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
