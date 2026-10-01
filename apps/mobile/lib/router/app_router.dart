import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../screens/consents_screen.dart';
import '../screens/decisions_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/incoming_referrals_screen.dart';
import '../screens/leaflet_screen.dart';
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
import '../screens/staff_notifications_screen.dart';
import '../screens/updates_screen.dart';
import '../screens/vaccination_screen.dart';
import '../screens/wait_screen.dart';
import '../screens/web_only_screen.dart';
import '../screens/worklist_screen.dart';
import '../state/session.dart';
import '../widgets/app_shell.dart';
import 'guards.dart';
import 'shells.dart';

/// Два shell'а с уникальными префиксами (go_router не матчит одинаковые пути в разных shell'ах).
/// Гражданин: `/home` (с вложенными `route` → `route/leaflet/:token`, `wait`, `medicines`, `vaccination`),
/// `/updates`, `/profile` (+ `security`, `notifications`, `consents`).
/// Врач: вкладки `/doctor/patients` (с `:ref` и `:ref/scribe`), `/doctor/incoming`, `/doctor/decisions`,
/// `/doctor/profile` (+ те же экраны аккаунта); вне вкладок — `/doctor/notifications` (колокольчик) и ассистент
/// нового направления `/doctor/referral?moCode=&profileCode=`. Скрайба без пациента и ассистента «от пациента» нет.
/// Роли без мобильного кабинета — `/web`. Вход: `/login`, `/login/otp` (второй фактор, логин и пароль приходят через
/// `extra`), `/login/forgot`. Вкладки и экраны скрываются по разрешениям (guards.dart); неизвестный адрес (в том
/// числе удалённые маршруты) ведёт на домашний экран роли, как catch-all в вебе. Внутри вкладок — `context.go`;
/// экраны вне вкладок открываются `context.push`, чтобы «назад» вернул на экран, с которого их открыли.
GoRouter buildRouter(Session session) => GoRouter(
      initialLocation: '/',
      refreshListenable: session,
      redirect: (_, state) => guard(session, state.matchedLocation),
      onException: (_, _, router) => router.go(session.home),
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
          builder: (_, _, shell) => CitizenShell(shell: shell, session: session),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'route',
                    builder: (_, _) => const RouteScreen(),
                    routes: [
                      GoRoute(path: 'leaflet/:token', builder: (_, state) => LeafletScreen(token: state.pathParameters['token']!)),
                    ],
                  ),
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
          builder: (_, _, shell) => DoctorShell(shell: shell, session: session),
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
                      GoRoute(path: 'scribe', builder: (_, state) => ScribeScreen(patientRef: state.pathParameters['ref'])),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/doctor/incoming', builder: (_, _) => const IncomingReferralsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/doctor/decisions', builder: (_, _) => const DecisionsScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/doctor/profile', builder: (_, _) => const ProfileScreen(), routes: _profileRoutes),
            ]),
          ],
        ),
        GoRoute(path: '/doctor/notifications', builder: (_, _) => const StaffNotificationsScreen()),
        GoRoute(
          path: '/doctor/referral',
          builder: (_, state) => ReferralScreen(moCode: state.uri.queryParameters['moCode'], profileCode: state.uri.queryParameters['profileCode']),
        ),
      ],
    );

/// Экраны аккаунта под профилем обоих shell'ов: безопасность, каналы уведомлений, данные и согласия.
final _profileRoutes = <RouteBase>[
  GoRoute(path: 'security', builder: (_, _) => const SecurityScreen()),
  GoRoute(path: 'notifications', builder: (_, _) => const NotificationSettingsScreen()),
  GoRoute(path: 'consents', builder: (_, _) => const ConsentsScreen()),
];

/// Вкладки гражданина: Главная · Уведомления · Профиль; на «Уведомлениях» — счётчик непрочитанного [unread]
/// (`CitizenNotificationsNotifier.unread`).
List<ShellDestination> citizenDestinations(S s, Session session, {int unread = 0}) => [
      ShellDestination(label: s.navHome, icon: Icons.home_outlined, path: '/home', branch: 0),
      ShellDestination(label: s.navUpdates, icon: Icons.notifications_none, path: '/updates', branch: 1, badge: unread, badgeLabel: s.bellUnread(unread)),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, path: '/profile', branch: 2),
    ];

/// Вкладки врачебного shell'а: Пациенты · Входящие · Решения · Профиль (Q-1). «Входящие» — всем в этом shell'е
/// (`worklist.view`), со счётчиком [pendingIncoming] переводов, ждущих подтверждения приёма
/// (`StaffBellNotifier.pendingIncomingCount`); «Решения» — только при `decisions.own`/`decisions.all`.
List<ShellDestination> doctorDestinations(S s, Session session, {int pendingIncoming = 0}) => [
      ShellDestination(label: s.navPatients, icon: Icons.people_outline, path: '/doctor/patients', branch: 0),
      ShellDestination(
        label: s.navIncoming,
        icon: Icons.move_to_inbox_outlined,
        path: '/doctor/incoming',
        branch: 1,
        badge: pendingIncoming,
        badgeLabel: s.bellPendingIncoming(pendingIncoming),
      ),
      if (session.canAny(const [Perm.decisionsOwn, Perm.decisionsAll]))
        ShellDestination(label: s.navDecisions, icon: Icons.history, path: '/doctor/decisions', branch: 2),
      ShellDestination(label: s.navProfile, icon: Icons.person_outline, path: '/doctor/profile', branch: 3),
    ];
