import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/confirm.dart';
import '../../core/models.dart';
import '../../core/registry.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.device});

  final KnownDevice device;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final StarApi _api;
  final _registry = DeviceRegistry();

  DeviceInfo? _info;
  PlaybackStatus? _status;
  List<AnimationInfo>? _anims;
  String? _selAnim;
  int _brightness = 255;
  int _tick = 0;
  bool _offline = false;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _api = StarApi(widget.device.ip);
    _refresh();
    _loadAnimations();
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await _api.status();
      if (_tick++ % 5 == 0) {
        final info = await _api.info();
        if (mounted) setState(() => _info = info);
        // Keep the registry entry (fw version) fresh.
        widget.device.fwVersion = info.fwVersion;
        await _registry.put(widget.device);
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _offline = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _loadAnimations() async {
    try {
      final a = await _api.animations();
      if (!mounted) return;
      setState(() {
        _anims = a;
        _offline = false;
        final names = a.map((x) => x.name).toSet();
        if (_selAnim == null || !names.contains(_selAnim)) {
          _selAnim = a.isEmpty ? null : a.first.name;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _guard(
    Future<void> Function() op, {
    bool spinner = false,
  }) async {
    if (spinner && mounted) setState(() => _busy = true);
    try {
      await op();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted && spinner) setState(() => _busy = false);
    }
  }

  Future<void> _play() async {
    final name = _selAnim;
    if (name == null) return;
    await _guard(() => _api.play(name, brightness: _brightness));
    _refresh();
  }

  Future<void> _stop() => _guard(() => _api.stop());

  Future<void> _setBrightness(int v) async {
    await _guard(() => _api.setBrightness(v));
  }

  Future<void> _delete(AnimationInfo a) async {
    final yes = await confirm(
      context,
      "Delete \"${a.name}\"?",
      "Removes it from the SD card.",
    );
    if (yes != true) return;
    await _guard(() => _api.deleteAnimation(a.name));
    _loadAnimations();
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["saf", "sbf"],
    );
    if (files.isEmpty) return;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      await _guard(() => _api.upload(f.name, bytes), spinner: true);
    }
    _loadAnimations();
  }

  Future<void> _flashFirmware() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ["bin"],
    );
    if (f == null) return;
    final yes = await confirm(
      context,
      "Flash \"${f.name}\"?",
      "The ESP32 reboots into the new firmware. Use the .bin from "
      "idf.py build, not the ELF.",
    );
    if (yes != true) return;
    final bytes = await f.readAsBytes();
    await _guard(() => _api.flashFirmware(bytes), spinner: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("OTA done, ornament is rebooting.")),
    );
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case "ota":
        await _flashFirmware();
      case "reboot":
        final yes = await confirm(
          context,
          "Reboot ornament?",
          "Takes about 10 seconds.",
        );
        if (yes == true) {
          await _guard(() async {
            try {
              await _api.reboot();
            } catch (_) {} // drops mid-reboot, that's fine
          });
        }
      case "reprovision":
        final yes = await confirm(
          context,
          "Re-configure Wi-Fi?",
          "The ornament forgets this network and reboots into BLE "
          "provisioning mode. You will need to re-add it.",
        );
        if (yes == true) {
          await _guard(() async {
            try {
              await _api.reprovision();
            } catch (_) {}
          });
          await _registry.remove(widget.device.id);
          if (mounted) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refresh();
              _loadAnimations();
            },
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: "ota",
                child: Text("Update ESP32 firmware (OTA)"),
              ),
              PopupMenuItem(value: "reboot", child: Text("Reboot")),
              PopupMenuItem(
                value: "reprovision",
                child: Text("Re-configure Wi-Fi"),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_offline) _offlineBanner(),
          _infoCard(),
          const SizedBox(height: 12),
          _playbackCard(),
          const SizedBox(height: 12),
          _animationsCard(),
        ],
      ),
    );
  }

  Widget _offlineBanner() => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.wifi_off),
          title: const Text("Ornament unreachable"),
          subtitle: Text("Expected at http://${widget.device.ip}"),
        ),
      );

  Widget _infoCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _info == null
              ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Device",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text("IP: ${_info!.ip}"),
                    Text("Wi-Fi: ${_info!.ssid}"),
                    Text("LEDs: ${_info!.ledCount}"),
                    Text("Uptime: ${_fmtUptime(_info!.uptimeS)}"),
                    Text("Free heap: ${_fmtKb(_info!.freeHeap)}"),
                    Text("ESP32 fw: ${_info!.fwVersion}"),
                    if (_info!.stmFwVersion != null)
                      Text("STM32 fw: ${_info!.stmFwVersion}"),
                  ],
                ),
        ),
      );

  Widget _playbackCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Playback",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_anims == null)
                const CircularProgressIndicator()
              else if (_anims!.isEmpty)
                const Text(
                  "No animations on the SD card yet. Import some below.",
                )
              else
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selAnim,
                  items: [
                    for (final a in _anims!)
                      DropdownMenuItem(
                        value: a.name,
                        child: Text(
                          "${a.name} "
                          "(${a.durationS.toStringAsFixed(1)} s, "
                          "${a.fps} fps)",
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selAnim = v),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed:
                        (_busy || _selAnim == null || _offline)
                            ? null
                            : _play,
                    child: const Text("Play"),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: (_busy || _offline) ? null : () => _stop(),
                    child: const Text("Stop"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Brightness"),
              Slider(
                value: _brightness.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: "$_brightness",
                onChanged: (v) => setState(() => _brightness = v.round()),
                onChangeEnd: (v) => _setBrightness(v.round()),
              ),
              if (_status != null)
                Text(
                  _status!.isPlaying
                      ? "Playing ${_status!.file} - "
                          "${_status!.fpsActual?.toStringAsFixed(1) ?? "?"} "
                          "fps, frame ${_status!.framesPlayed}, buffer "
                          "${_status!.bufferFrames}, drops ${_status!.drops}"
                      : "Idle",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );

  Widget _animationsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "SD card",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file),
                    tooltip: "Import .saf / .sbf",
                    onPressed: _busy ? null : _upload,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: "Refresh",
                    onPressed: _busy ? null : _loadAnimations,
                  ),
                ],
              ),
              if (_anims != null)
                for (final a in _anims!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.name),
                    subtitle: Text(
                      "${_fmtKb(a.sizeBytes)} - ${a.frames} frames - "
                      "${a.hasCompiled ? "playable" : "master only"}",
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _delete(a),
                    ),
                  ),
              if (_anims != null && _anims!.isEmpty)
                const Text("Empty - import .saf and .sbf files."),
            ],
          ),
        ),
      );
}

String _fmtUptime(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return "$h h $m min";
}

String _fmtKb(int b) => "${(b / 1024).round()} KB";
