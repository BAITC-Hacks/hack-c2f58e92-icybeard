import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../screens/decisions_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/medicines_screen.dart';
import '../screens/patient_route_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/referral_screen.dart';
import '../screens/route_screen.dart';
import '../screens/scribe_screen.dart';
import '../screens/updates_screen.dart';
import '../screens/vaccination_screen.dart';
import '../screens/wait_screen.dart';
import '../screens/worklist_screen.dart';
import '../state/session.dart';
import '../widgets/app_shell.dart';
import 'guards.dart';

/// Два shell'а с уникальными префиксами (go_router не матчит одинаковые пути в разных shell'ах):
/// citizen — `/home` (с вложенными `route`, `wait`, `medicines`, `vaccination`), `/updates`, `/profile`;
/// doctor — `/doctor/patients` (с `:ref` и `:ref/referral`), `/doctor/referral` (с `decisions`), `/doctor/scribe`,
/// `/doctor/profile`. Переходы — `context.go`, чтобы стек ветки и кнопка «назад» были согласованы.
GoRouter buildRouter(Session session) => GoRouter(
      initialLocation: '/',
      refreshListenable: session,
      redirect: (_, state) => guard(session, state.matchedLocation),
      routes: [
        GoRoute(path: '/', redirect: (_, _) => session.home),
        GoRoute(path: '/login', builder: (_, state) => LoginScreen(from: state.uri.queryParameters['from'])),
        StatefulShellRoute.indexedStack(
          builder: (context, _, shell) => AppShell(shell: shell, destinations: _citizenDestinations(S.at(context))),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(path: 'route', builder: (_, _) => const RouteScreen()),
                  GoRoute(
                    path: 'wait',
                    builder: (_, state) => WaitScreen(
                      regionKato: state.uri.queryParameters['region'],
                      profileCode: state.uri.queryParameters['profile'],
                    ),
                  ),
                  GoRoute(path: 'medicines', builder: (_, _) => const MedicinesScreen()),
                  GoRoute(path: 'vaccination', builder: (_, _) => const VaccinationScreen()),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/updates', builder: (_, _) => const UpdatesScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
          ],
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, _, shell) => AppShell(shell: shell, destinations: _doctorDestinations(S.at(context))),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/doctor/patients',
                builder: (_, _) => const WorklistScreen(),
                routes: [
                  GoRoute(
                    path: ':ref',
                    builder: (_, state) => PatientRouteScreen(patientRef: state.pathParameters['ref']!, preview: state.extra as WorklistItem?),
                    routes: [
                      GoRoute(
                        path: 'referral',
                        builder: (_, state) => ReferralScreen(
                          patientRef: state.pathParameters['ref'],
                          moCode: state.uri.queryParameters['moCode'],
                          profileCode: state.uri.queryParameters['profileCode'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/doctor/referral',
                builder: (_, state) => ReferralScreen(moCode: state.uri.queryParameters['moCode'], profileCode: state.uri.queryParameters['profileCode']),
                routes: [GoRoute(path: 'decisions', builder: (_, _) => const DecisionsScreen())],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/doctor/scribe', builder: (_, _) => const ScribeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/doctor/profile', builder: (_, _) => const ProfileScreen())]),
          ],
        ),
      ],
    );

List<ShellDestination> _citizenDestinations(S s) => [
      ShellDestination(label: s.navHome, icon: Icons.home_outlined, selectedIcon: Icons.home),
      ShellDestination(label: s.navUpdates, icon: Icons.notifications_none, selectedIcon: Icons.notifications),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, selectedIcon: Icons.person),
    ];

List<ShellDestination> _doctorDestinations(S s) => [
      ShellDestination(label: s.navPatients, icon: Icons.people_outline, selectedIcon: Icons.people),
      ShellDestination(label: s.navReferral, icon: Icons.assignment_outlined, selectedIcon: Icons.assignment),
      ShellDestination(label: s.navScribe, icon: Icons.mic_none, selectedIcon: Icons.mic),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, selectedIcon: Icons.person),
    ];
