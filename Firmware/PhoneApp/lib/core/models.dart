class KnownDevice {
  KnownDevice({
    required this.id,
    required this.name,
    required this.ip,
    this.fwVersion,
  });

  final String id;
  String name;
  String ip;
  String? fwVersion;

  Map<String, dynamic> toMap() => {
        "id": id,
        "name": name,
        "ip": ip,
        "fw_version": fwVersion,
      };

  static KnownDevice fromMap(Map<String, dynamic> m) => KnownDevice(
        id: m["id"] as String,
        name: m["name"] as String,
        ip: m["ip"] as String,
        fwVersion: m["fw_version"] as String?,
      );
}

/// GET /api/info -- all numbers are JSON integers.
class DeviceInfo {
  DeviceInfo({
    required this.fwVersion,
    required this.stmFwVersion,
    required this.ledCount,
    required this.uptimeS,
    required this.freeHeap,
    required this.ip,
    required this.ssid,
    required this.rssi,
  });

  final String fwVersion;
  final String? stmFwVersion;
  final int ledCount;
  final int uptimeS;
  final int freeHeap;
  final String ip;
  final String ssid;
  final int? rssi;

  static DeviceInfo fromJson(Map<String, dynamic> j) => DeviceInfo(
        fwVersion: j["fw_version"] as String,
        stmFwVersion: j["stm_fw_version"] as String?,
        ledCount: j["led_count"] as int,
        uptimeS: j["uptime_s"] as int,
        freeHeap: j["free_heap"] as int,
        ip: j["ip"] as String,
        ssid: j["ssid"] as String,
        rssi: j["rssi"] as int?,
      );
}

/// One entry of GET /api/animations -> {"animations": [ ... ]}
class AnimationInfo {
  AnimationInfo({
    required this.name,
    required this.durationS,
    required this.fps,
    required this.frames,
    required this.sizeBytes,
    required this.hasCompiled,
  });

  final String name;
  final double durationS;
  final int fps;
  final int frames;
  final int sizeBytes;

  /// A matching .sbf exists on the SD card -> playable right now.
  final bool hasCompiled;

  static AnimationInfo fromJson(Map<String, dynamic> j) => AnimationInfo(
        name: j["name"] as String,
        durationS: (j["duration_s"] as num).toDouble(),
        fps: j["fps"] as int,
        frames: j["frames"] as int,
        sizeBytes: j["size_bytes"] as int,
        hasCompiled: (j["has_sbf"] ?? false) as bool,
      );
}

/// GET /api/status -- telemetry relayed from the STM32 heartbeat.
class PlaybackStatus {
  PlaybackStatus({
    required this.state,
    required this.file,
    required this.framesPlayed,
    required this.bufferFrames,
    required this.drops,
    required this.fpsActual,
  });

  final String state; // "idle" | "playing"
  final String? file;
  final int framesPlayed;
  final int bufferFrames; // STM32 ring-buffer occupancy
  final int drops;
  final double? fpsActual;

  bool get isPlaying => state == "playing";

  static PlaybackStatus fromJson(Map<String, dynamic> j) => PlaybackStatus(
        state: j["state"] as String,
        file: j["file"] as String?,
        framesPlayed: (j["frames_played"] ?? 0) as int,
        bufferFrames: (j["buffer"] ?? 0) as int,
        drops: (j["drops"] ?? 0) as int,
        fpsActual: j["fps_actual"] == null
            ? null
            : (j["fps_actual"] as num).toDouble(),
      );
}
