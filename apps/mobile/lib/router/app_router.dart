import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../screens/decisions_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/medicines_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/patient_route_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/referral_screen.dart';
import '../screens/route_screen.dart';
import '../screens/scribe_screen.dart';
import '../screens/security_screen.dart';
import '../screens/updates_screen.dart';
import '../screens/vaccination_screen.dart';
import '../screens/wait_screen.dart';
import '../screens/web_only_screen.dart';
import '../screens/worklist_screen.dart';
import '../state/session.dart';
import '../widgets/app_shell.dart';
import 'guards.dart';

/// Два shell'а с уникальными префиксами (go_router не матчит одинаковые пути в разных shell'ах):
/// citizen — `/home` (с вложенными `route`, `wait`, `medicines`, `vaccination`), `/updates`, `/profile` (+ `security`,
/// `notifications`); doctor — `/doctor/patients` (с `:ref`, `:ref/referral`, `:ref/scribe`), `/doctor/decisions`,
/// `/doctor/profile` (+ `security`, `notifications`). Ассистент направления и скрайб без пациента (`/doctor/referral`, `/doctor/scribe`) живут вне
/// вкладок. Роли без мобильного кабинета — `/web`. Вход: `/login`, `/login/otp` (второй фактор, логин и пароль
/// приходят через `extra`), `/login/forgot`. Вкладки и экраны скрываются по разрешениям (guards.dart).
/// Переходы — `context.go`, чтобы стек ветки и кнопка «назад» были согласованы.
GoRouter buildRouter(Session session) => GoRouter(
      initialLocation: '/',
      refreshListenable: session,
      redirect: (_, state) => guard(session, state.matchedLocation),
      routes: [
        GoRoute(path: '/', redirect: (_, _) => session.home),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(from: state.uri.queryParameters['from']),
          routes: [
            GoRoute(
              path: 'otp',
              redirect: (_, state) => state.extra is OtpRequest ? null : '/login',
              builder: (_, state) => OtpScreen(request: state.extra! as OtpRequest),
            ),
            GoRoute(path: 'forgot', builder: (_, _) => const ForgotPasswordScreen()),
          ],
        ),
        GoRoute(path: '/web', builder: (_, _) => const WebOnlyScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, _, shell) => AppShell(shell: shell, destinations: citizenDestinations(S.at(context), session)),
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
            StatefulShellBranch(routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen(), routes: _profileRoutes),
            ]),
          ],
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, _, shell) => AppShell(shell: shell, destinations: doctorDestinations(S.at(context), session)),
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
                      GoRoute(path: 'scribe', builder: (_, state) => ScribeScreen(patientRef: state.pathParameters['ref'])),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/doctor/decisions', builder: (_, _) => const DecisionsScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/doctor/profile', builder: (_, _) => const ProfileScreen(), routes: _profileRoutes),
            ]),
          ],
        ),
        GoRoute(
          path: '/doctor/referral',
          builder: (_, state) => ReferralScreen(moCode: state.uri.queryParameters['moCode'], profileCode: state.uri.queryParameters['profileCode']),
        ),
        GoRoute(path: '/doctor/scribe', builder: (_, _) => const ScribeScreen()),
      ],
    );

/// Экраны аккаунта под профилем обоих shell'ов: безопасность и каналы уведомлений.
final _profileRoutes = <RouteBase>[
  GoRoute(path: 'security', builder: (_, _) => const SecurityScreen()),
  GoRoute(path: 'notifications', builder: (_, _) => const NotificationSettingsScreen()),
];

/// Вкладки гражданина: Главная · Уведомления · Профиль.
List<ShellDestination> citizenDestinations(S s, Session session) => [
      ShellDestination(label: s.navHome, icon: Icons.home_outlined, path: '/home', branch: 0),
      ShellDestination(label: s.navUpdates, icon: Icons.notifications_none, path: '/updates', branch: 1),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, path: '/profile', branch: 2),
    ];

/// Вкладки врача: Пациенты · Решения · Профиль (ассистент и скрайб открываются из маршрута пациента). «Решения» —
/// только при `decisions.own`/`decisions.all`.
List<ShellDestination> doctorDestinations(S s, Session session) => [
      ShellDestination(label: s.navPatients, icon: Icons.people_outline, path: '/doctor/patients', branch: 0),
      if (session.canAny(const [Perm.decisionsOwn, Perm.decisionsAll]))
        ShellDestination(label: s.navDecisions, icon: Icons.history, path: '/doctor/decisions', branch: 1),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, path: '/doctor/profile', branch: 2),
    ];
