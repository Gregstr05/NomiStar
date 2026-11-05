import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class DeviceRegistry {
  static const String _key = "star.devices";

  Future<List<KnownDevice>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => KnownDevice.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> put(KnownDevice device) async {
    final devices = await load();
    devices.removeWhere((d) => d.id == device.id);
    devices.add(device);
    await _save(devices);
  }

  Future<void> remove(String id) async {
    final devices = await load();
    devices.removeWhere((d) => d.id == id);
    await _save(devices);
  }

  Future<void> _save(List<KnownDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(devices.map((d) => d.toMap()).toList());
    await prefs.setString(_key, raw);
  }
}
