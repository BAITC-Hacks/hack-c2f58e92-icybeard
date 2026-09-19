import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/decisions_screen.dart';
import 'screens/home_screen.dart';
import 'screens/medicines_screen.dart';
import 'screens/referral_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vaccination_screen.dart';
import 'screens/wait_screen.dart';
import 'screens/worklist_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/wait', builder: (_, _) => const WaitScreen()),
    GoRoute(path: '/medicines', builder: (_, _) => const MedicinesScreen()),
    GoRoute(path: '/vaccination', builder: (_, _) => const VaccinationScreen()),
    GoRoute(path: '/worklist', builder: (_, _) => const WorklistScreen()),
    GoRoute(path: '/referral', builder: (_, state) => ReferralScreen(moCode: state.uri.queryParameters['moCode'], profileCode: state.uri.queryParameters['profileCode'])),
    GoRoute(path: '/decisions', builder: (_, _) => const DecisionsScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

class DarumenApp extends StatelessWidget {
  const DarumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Darumen Care',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0B7285), useMaterial3: true),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
