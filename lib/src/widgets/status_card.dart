import 'package:flutter/material.dart';

import '../api/models.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.status});
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(status.connected ? 'Connected' : 'Not connected'),
        subtitle: Text(status.endpoint),
      ),
    );
  }
}

