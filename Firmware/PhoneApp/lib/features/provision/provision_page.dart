import 'dart:async';
import 'dart:io';

import 'package:esp_prov/esp_prov.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/models.dart';
import '../../core/protocol.dart';
import '../../core/registry.dart';
import '../dashboard/dashboard_page.dart';

enum _Phase { scanning, wifiList, provisioning, done }

class ProvisionPage extends StatefulWidget {
  const ProvisionPage({super.key});

  @override
  State<ProvisionPage> createState() => _ProvisionPageState();
}

class _ProvisionPageState extends State<ProvisionPage> {
  final _prov = EspProvisioning();
  final _registry = DeviceRegistry();
  final _pass = TextEditingController();
  final _manualSsid = TextEditingController();

  StreamSubscription<dynamic>? _scanSub;
  dynamic _session; // esp_prov session (kept dynamic on purpose)

  _Phase _phase = _Phase.scanning;
  bool _busy = true;
  String _log = "Requesting permissions...";
  String? _error;

  final Map<String, dynamic> _devices = {}; // label -> BLE advertisement
  List<dynamic> _networks = [];
  String? _selSsid;
  KnownDevice? _saved;
  String? _newIp;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _pass.dispose();
    _manualSsid.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (await _ensurePermissions()) {
      _startScan();
    }
  }

  Future<bool> _ensurePermissions() async {
    if (Platform.isIOS) {
      return (await Permission.bluetooth.request()).isGranted;
    }
    if (!Platform.isAndroid) return true;

    // Android 12+ -- all we actually need.
    final required = [Permission.bluetoothScan, Permission.bluetoothConnect];

    // Android <=11 needs location for scan results; harmless to also
    // request on 12+ where it's simply ignored. Never *required* by us.
    final optional = [Permission.locationWhenInUse];

    final statuses = await [...required, ...optional].request();
    for (final e in statuses.entries) {
      debugPrint("[perm] ${e.key} -> ${e.value}");
    }

    final missing = statuses.entries
        .where((e) => required.contains(e.key) && !e.value.isGranted)
        .toList();
    if (missing.isEmpty) return true;

    if (missing.any((e) => e.value.isPermanentlyDenied)) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Permission disabled"),
          content: const Text(
            "Bluetooth permission was permanently denied. Enable it in "
            "the system settings for this app, then come back.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Later"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text("Open settings"),
            ),
          ],
        ),
      );
      return false;
    }

    if (mounted) {
      setState(() => _error = "Bluetooth permission was denied.");
    }
    return false;
  }

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _phase = _Phase.scanning;
      _busy = true;
      _error = null;
      _devices.clear();
      _log = "Scanning for the ornament over BLE...";
    });
    _scanSub = _prov.scan(namePrefix: StarProtocol.bleNamePrefix).listen(
          (device) {
            final label = _labelOf(device);
            if (!_devices.containsKey(label)) {
              _devices[label] = device;
              if (mounted) setState(() {});
            }
          },
          onError: (Object e) => setState(() {
                _busy = false;
                _error = "Scan failed: $e";
              }),
          onDone: () {
            if (mounted) setState(() => _busy = false);
          },
        );
  }

  // esp_prov is young; guard dynamic access so the UI never crashes
  // just because a field name differs between package versions.
  String _labelOf(dynamic device) {
    try {
      final n = device.name;
      if (n is String && n.isNotEmpty) return n;
    } catch (_) {}
    return "Star Topper";
  }

  Future<void> _connect(dynamic device) async {
    _scanSub?.cancel();  // scanning while connecting triggers 133 on Android
    setState(() {
      _busy = true;
      _log = "Connecting over BLE...";
      _error = null;
    });

    const attempts = 4;
    for (var i = 1; i <= attempts; i++) {
      try {
        // Let the scan tear down and the stack settle first -- a
        // connect fired mid-scan is the classic 133 trigger.
        await Future<void>.delayed(
            Duration(milliseconds: i == 1 ? 500 : 1500));
        _session = await device.connect(
          credentials: const ProvCredentials.security2(
            username: StarProtocol.provUsername,
            password: StarProtocol.provPassword,
          ),
        );
        _networks = await _session.wifi.scan();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _phase = _Phase.wifiList;
        });
        return;
      } catch (e) {
        if (i == attempts) {
          setState(() {
            _busy = false;
            _error = "Could not connect or establish secure session: $e";
          });
          return;
        }
        setState(() => _log = "Connect attempt $i failed, retrying...");
      }
    }
  }

  String? _ssidOf(dynamic network) {
    try {
      final s = network.ssid;
      if (s is String) return s;
    } catch (_) {}
    return null;
  }

  String _rssiOf(dynamic network) {
    try {
      final r = network.rssi;
      if (r is int) return "$r dBm";
    } catch (_) {}
    return "";
  }

  Future<void> _joinPressed() async {
    final ssid = _selSsid ?? _manualSsid.text.trim();
    if (ssid.isEmpty) return;
    await _provision(ssid, _pass.text);
  }

  Future<void> _provision(String ssid, String pass) async {
    setState(() {
      _busy = true;
      _phase = _Phase.provisioning;
      _log = "Sending credentials to the ornament...";
      _error = null;
    });
    String? ip;
    try {
      final stream = _session.wifi.provision(ssid: ssid, passphrase: pass);
      await for (final st in stream) {
        if (st is WifiConnected) {
          final v = st.ip4;
          ip = (v == null) ? null : v.toString();
          setState(() => _log = "Connected to Wi-Fi!");
        } else if (st is WifiFailed) {
          setState(() => _log = "Failed: ${st.reason.name}");
        } else {
          setState(() => _log = "Status: ${st.runtimeType}");
        }
      }
    } catch (e) {
      // After WifiConnected the firmware stops provisioning and BLE
      // drops ~1 s later. If we already have an IP, that's success.
      if (ip == null) {
        setState(() {
          _busy = false;
          _error = "Provisioning error: $e";
        });
        return;
      }
    }
    try {
      await _session.close();
    } catch (_) {}

    final dev = KnownDevice(
      id: "star-$ssid",
      name: "Star Topper",
      ip: ip ?? "unknown",
    );
    await _registry.put(dev);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _phase = _Phase.done;
      _saved = dev;
      _newIp = ip;
    });
  }

  void _openDashboard() {
    final dev = _saved;
    if (dev == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DashboardPage(device: dev)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add a Star Topper")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
              ),
            ),
          const SizedBox(height: 8),
          ..._phaseChildren(),
        ],
      ),
    );
  }

  List<Widget> _phaseChildren() {
    switch (_phase) {
      case _Phase.scanning:
        return [
          Text(_log),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          for (final e in _devices.entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.star),
                title: Text(e.key),
                subtitle: const Text("Tap to connect"),
                onTap: () => _connect(e.value),
              ),
            ),
          if (!_busy && _devices.isEmpty)
            const Text("No ornament found. Make sure it is powered on "
                "and in provisioning mode."),
          if (!_busy)
            FilledButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text("Rescan"),
            ),
        ];
      case _Phase.wifiList:
        return [
          const Text("Networks the ornament can see:"),
          if (_busy) const LinearProgressIndicator(),
          ..._wifiTiles(),
          const SizedBox(height: 8),
          TextField(
            controller: _manualSsid,
            decoration: const InputDecoration(
              labelText: "...or type the SSID manually",
            ),
          ),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Password"),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _joinPressed,
            icon: const Icon(Icons.wifi),
            label: const Text("Connect ornament to this Wi-Fi"),
          ),
        ];
      case _Phase.provisioning:
        return [
          const SizedBox(height: 48),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(child: Text(_log)),
        ];
      case _Phase.done:
        return [
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Icons.celebration,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text("The ornament joined your Wi-Fi.")),
          Center(child: Text("Address: http://$_newIp")),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _openDashboard,
              child: const Text("Open the dashboard"),
            ),
          ),
        ];
    }
  }

  List<Widget> _wifiTiles() {
    final tiles = <Widget>[];
    final seen = <String>{};
    for (final n in _networks) {
      final ssid = _ssidOf(n);
      if (ssid == null || !seen.add(ssid)) continue;
      tiles.add(
        RadioListTile<String>(
          value: ssid,
          groupValue: _selSsid,
          title: Text(ssid),
          subtitle: Text(_rssiOf(n)),
          onChanged: (v) => setState(() => _selSsid = v),
        ),
      );
    }
    return tiles;
  }
}
