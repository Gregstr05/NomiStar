import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'protocol.dart';

class StarApiError implements Exception {
  StarApiError(this.message);
  final String message;

  @override
  String toString() => message;
}

class StarApi {
  StarApi(this.ip);

  /// Current LAN address of the ornament (no scheme; port 80).
  final String ip;

  static const Duration _t = Duration(seconds: 5);

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.http(ip, path, query);

  void _check(http.Response r) {
    if (r.statusCode >= 300) {
      throw StarApiError("HTTP ${r.statusCode} from ${r.request?.url.path}");
    }
  }

  Future<DeviceInfo> info() async {
    final r = await http.get(_u(StarProtocol.epInfo)).timeout(_t);
    _check(r);
    return DeviceInfo.fromJson(jsonDecode(r.body));
  }

  Future<List<AnimationInfo>> animations() async {
    final r = await http.get(_u(StarProtocol.epAnimations)).timeout(_t);
    _check(r);
    final list = jsonDecode(r.body)["animations"] as List<dynamic>;
    return list
        .map((e) => AnimationInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlaybackStatus> status() async {
    final r = await http.get(_u(StarProtocol.epStatus)).timeout(_t);
    _check(r);
    return PlaybackStatus.fromJson(jsonDecode(r.body));
  }

  Future<void> play(String name, {int? brightness}) async {
    final body = jsonEncode({
      "name": name,
      if (brightness != null) "brightness": brightness,
    });
    final r = await http
        .post(
          _u(StarProtocol.epPlay),
          headers: {"content-type": "application/json"},
          body: body,
        )
        .timeout(_t);
    _check(r);
  }

  Future<void> stop() => _postJson(StarProtocol.epStop, {});

  Future<void> setBrightness(int value) =>
      _postJson(StarProtocol.epBrightness, {"value": value});

  Future<void> deleteAnimation(String name) async {
    final r = await http
        .delete(_u(StarProtocol.epAnimations, {"name": name}))
        .timeout(_t);
    _check(r);
  }

  /// Raw-body upload. esp_http_server hates multipart parsing; a plain
  /// octet-stream body with the filename in the query string is trivial
  /// to implement on both ends. Upload .saf (master) and .sbf (compiled).
  Future<void> upload(String filename, List<int> bytes) async {
    final r = await http
        .post(
          _u(StarProtocol.epUpload, {"name": filename}),
          headers: {"content-type": "application/octet-stream"},
          body: bytes,
        )
        .timeout(const Duration(minutes: 2));
    _check(r);
  }

  /// ESP32 OTA
  Future<void> flashFirmware(List<int> appBin) async {
    final r = await http
        .post(
          _u(StarProtocol.epOta),
          headers: {"content-type": "application/octet-stream"},
          body: appBin,
        )
        .timeout(const Duration(minutes: 5));
    _check(r);
  }

  /// Connection drops mid-reboot; callers should catch, not a real error.
  Future<void> reboot() => _postJson(StarProtocol.epReboot, {});

  /// Wipe Wi-Fi creds in NVS; device reboots into BLE provisioning mode.
  Future<void> reprovision() => _postJson(StarProtocol.epReprovision, {});

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(
          _u(path),
          headers: {"content-type": "application/json"},
          body: jsonEncode(body),
        )
        .timeout(_t);
    _check(r);
  }
}
