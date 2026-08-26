import 'package:flutter/material.dart';

import 'api/models.dart';
import 'widgets/status_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    const status = ConnectionStatus(connected: false, endpoint: 'unset');
    return Scaffold(
      appBar: AppBar(title: const Text('Opto Sync')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: StatusCard(status: status),
      ),
    );
  }
}

