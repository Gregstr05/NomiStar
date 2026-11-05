import 'package:flutter/material.dart';

import '../../core/confirm.dart';
import '../../core/models.dart';
import '../../core/registry.dart';
import '../dashboard/dashboard_page.dart';
import '../provision/provision_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _registry = DeviceRegistry();
  List<KnownDevice> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final d = await _registry.load();
    if (!mounted) return;
    setState(() {
      _devices = d;
      _loading = false;
    });
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProvisionPage()),
    );
    _reload();
  }

  Future<void> _open(KnownDevice d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DashboardPage(device: d)),
    );
    _reload();
  }

  Future<void> _forget(KnownDevice d) async {
    final yes = await confirm(
      context,
      "Forget ${d.name}?",
      "Only removes it from this app. Re-add it any time.",
    );
    if (yes != true) return;
    await _registry.remove(d.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Star Toppers")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text("Add ornament"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [for (final d in _devices) _card(d)],
                ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              "No ornaments yet.\nPlug yours in and tap \"Add ornament\".",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _card(KnownDevice d) => Card(
        child: ListTile(
          leading: const Icon(Icons.star),
          title: Text(d.name),
          subtitle: Text(
            "http://${d.ip}  -  fw ${d.fwVersion ?? "?"}",
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _forget(d),
          ),
          onTap: () => _open(d),
        ),
      );
}
