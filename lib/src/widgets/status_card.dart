import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/sync_lifecycle.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.lifecycle,
    this.error,
  });

  final ConnectionStatus status;
  final SyncLifecycleSnapshot lifecycle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(status.connected ? 'Connected' : 'Not connected'),
        subtitle: Text(
          '${status.endpoint}\n'
          'Lifecycle: ${lifecycle.phaseLabel}\n'
          'Generation: ${lifecycle.generation}'
          '${error == null ? '' : '\n$error'}',
        ),
      ),
    );
  }
}
