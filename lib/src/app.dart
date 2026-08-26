import 'package:flutter/material.dart';

import 'home_page.dart';
import 'theme.dart';

class OptoSyncApp extends StatelessWidget {
  const OptoSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Opto Sync',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const HomePage(),
    );
  }
}

