import '../../config/env.dart';

/// Куда ведут входящие направления и уведомления персонала (маршруты `lib/router/app_router.dart`).

/// Вкладка «Входящие».
const incomingPath = '/doctor/incoming';

/// Страница маршрута пациента — там же «Снять с листа ожидания» (Q-18).
String patientRoutePath(String patientRef) => '/doctor/patients/${Uri.encodeComponent(patientRef)}';

/// Скрайб для пациента (нужен `scribe.use`).
String patientScribePath(String patientRef) => '${patientRoutePath(patientRef)}/scribe';

/// Входящие направления в веб-кабинете — там больницу выбирает пользователь без своей (Q-2).
Uri incomingWebUri() => Uri.parse('${Env.webBase}/doctor/referrals/incoming');
