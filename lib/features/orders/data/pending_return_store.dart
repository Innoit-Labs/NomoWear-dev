import 'package:shared_preferences/shared_preferences.dart';

/// Tracks orders whose return was submitted (including waitlisted) while the
/// backend may still report `returnStatus: ACTIVE` until admin approval.
class PendingReturnStore {
  PendingReturnStore._();

  static final PendingReturnStore instance = PendingReturnStore._();

  static const _prefsKey = 'pending_return_order_ids';

  final Set<String> _ids = <String>{};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _readPrefs();
  }

  Future<void> _readPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
    _ids
      ..clear()
      ..addAll(raw.map((e) => e.trim()).where((e) => e.isNotEmpty));
    _loaded = true;
  }

  bool contains(String orderId) {
    final id = orderId.trim();
    if (id.isEmpty) return false;
    return _ids.contains(id);
  }

  Future<void> mark(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    await ensureLoaded();
    if (_ids.add(id)) {
      await _persist();
    }
  }

  Future<void> clear(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    await ensureLoaded();
    if (_ids.remove(id)) {
      await _persist();
    }
  }

  Future<void> clearAll() async {
    _ids.clear();
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Drop local pending flags once the API reflects return flow / completion.
  Future<void> syncWithApiFlags({
    required String orderId,
    required bool isInReturnFlow,
    required bool isReturnComplete,
  }) async {
    if (isInReturnFlow || isReturnComplete) {
      await clear(orderId);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _ids.toList(growable: false));
  }
}
