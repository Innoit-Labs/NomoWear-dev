import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks orders with submitted customer refund requests (waitlist numbers).
class PendingRefundStore {
  PendingRefundStore._();

  static final PendingRefundStore instance = PendingRefundStore._();

  static const _prefsKey = 'pending_refund_requests_map';

  final Map<String, String> _orderRefundMap = <String, String>{};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _readPrefs();
  }

  Future<void> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _orderRefundMap.clear();
          decoded.forEach((key, value) {
            final k = key.toString().trim();
            final v = value.toString().trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              _orderRefundMap[k] = v;
            }
          });
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_orderRefundMap));
    } catch (_) {}
  }

  String? getWaitlistNumber(String orderId) {
    final id = orderId.trim();
    if (id.isEmpty) return null;
    return _orderRefundMap[id];
  }

  bool hasRefundRequest(String orderId) {
    return getWaitlistNumber(orderId) != null;
  }

  Future<void> saveRefundRequest({
    required String orderId,
    required String waitlistNumber,
  }) async {
    final id = orderId.trim();
    final wl = waitlistNumber.trim();
    if (id.isEmpty || wl.isEmpty) return;
    await ensureLoaded();
    _orderRefundMap[id] = wl;
    await _persist();
  }

  Future<void> clear(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    await ensureLoaded();
    if (_orderRefundMap.remove(id) != null) {
      await _persist();
    }
  }

  Future<void> clearAll() async {
    _orderRefundMap.clear();
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
