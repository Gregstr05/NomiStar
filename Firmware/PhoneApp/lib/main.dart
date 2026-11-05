import 'package:flutter/material.dart';

import 'features/devices/devices_page.dart';

void main() => runApp(const StarCompanionApp());

class StarCompanionApp extends StatelessWidget {
  const StarCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Star Companion",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffa855f7),
          brightness: Brightness.dark,
        ),
      ),
      home: const DevicesPage(),
    );
  }
}
