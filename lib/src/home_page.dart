import 'package:flutter/material.dart';

import 'api/client.dart';
import 'app_lifecycle_controller.dart';
import 'widgets/status_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleController _controller;
  late final ProbeOutcome _outcome;

  @override
  void initState() {
    super.initState();
    _controller = AppLifecycleController(
      client: const ApiClient(baseUrl: 'http://127.0.0.1:8080'),
    );
    _outcome = _controller.probe();
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Opto Sync')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: StatusCard(
          status: _outcome.status,
          lifecycle: _outcome.lifecycle,
          error: _outcome.error,
        ),
      ),
    );
  }
}
