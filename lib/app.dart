import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/journeys/journey_list_screen.dart';

class BehangApp extends StatelessWidget {
  const BehangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Behang',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const JourneyListScreen(),
    );
  }
}
