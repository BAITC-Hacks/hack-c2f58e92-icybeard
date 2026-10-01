import 'dart:math' as math;

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../format.dart';

/// Чистая логика экрана «Сколько ждут» (веб `WaitView.vue`): полосы «Где быстрее в регионе», сравнение со средним по
/// региону, сезонная строка NHS и правило кнопки «Попросить рассмотреть». Без виджетов — под юнит-тесты.

/// Самая короткая полоса — 3 % ширины, чтобы больница с почти нулевым сроком не пропадала.
const _minBarShare = 0.03;

/// Доля ширины полосы: срок больницы относительно самого долгого в списке; самый долгий — не меньше одного дня,
/// как в вебе (`Math.max(1, …)`), чтобы не делить на ноль.
double waitBarShare(double p50, double maxP50) => (p50 / math.max(1, maxP50)).clamp(_minBarShare, 1.0).toDouble();

/// Сравнение больницы со средним по региону на округлённых днях, которые видит человек: «на N дн. быстрее
/// среднего», «на N дн. дольше среднего», «как в среднем по региону»; null — среднего нет.
String? waitCompareText(S s, {required double? regionP50, required double p50}) {
  final diff = roundedDaysDiff(regionP50, p50);
  if (diff == null) {
    return null;
  }
  return diff > 0 ? s.waitFasterThanAvg(diff) : (diff < 0 ? s.waitSlowerThanAvg(-diff) : s.waitSameAsAvg);
}

/// Число у больницы зелёное, только если там ждут меньше, чем в среднем по региону (на округлённых днях).
bool waitIsFaster({required double? regionP50, required double p50}) => (roundedDaysDiff(regionP50, p50) ?? 0) > 0;

/// Точка сезонности `GET /refdata/seasonality`: множитель месяца [month] (1…12) ряда [seriesId].
class SeasonPoint {
  const SeasonPoint({required this.seriesId, required this.month, required this.multiplier});

  /// Ряд листа ожидания NHS RTT — единственный, по которому строится подсказка.
  static const waitingListSeries = 'rtt_waiting_list';

  final String seriesId;
  final int month;
  final double multiplier;

  factory SeasonPoint.fromJson(Map<String, dynamic> json) => SeasonPoint(
        seriesId: json['seriesId'] as String? ?? '',
        month: (json['month'] as num?)?.toInt() ?? 0,
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0,
      );
}

/// Сколько месяцев вперёд показывает сезонная подсказка.
const _seasonalSteps = 3;

/// Порог «без изменений» в процентах: меньше — знак «±».
const _seasonalFlat = 0.05;

/// Как обычно меняется лист ожидания NHS в ближайшие три месяца относительно текущего [currentMonth] (1…12):
/// «в ноябре +1.2 %, в декабре −5.0 %, в январе ±0.0 %». null — ряда листа ожидания нет целиком (12 месяцев).
String? seasonalHint(S s, List<SeasonPoint> points, {required int currentMonth}) {
  final waiting = points.where((p) => p.seriesId == SeasonPoint.waitingListSeries).toList();
  if (waiting.length != 12) {
    return null;
  }
  final byMonth = {for (final p in waiting) p.month: p.multiplier};
  final current = byMonth[currentMonth];
  if (current == null || current == 0) {
    return null;
  }
  final parts = <String>[];
  for (var step = 1; step <= _seasonalSteps; step++) {
    final month = ((currentMonth - 1 + step) % 12) + 1;
    final next = byMonth[month];
    if (next == null) {
      return null;
    }
    final delta = (next - current) / current * 100;
    final sign = delta > _seasonalFlat ? '+' : (delta < -_seasonalFlat ? '−' : '±');
    parts.add('${s.waitMonthIn(month)} $sign${delta.abs().toStringAsFixed(1)} %');
  }
  return parts.join(', ');
}

/// Можно ли попросить врача рассмотреть больницу [moCode] с экрана «Сколько ждут» (решения Q8, Q23): маршрут
/// разрешает `request_transfer`, выбраны регион и профиль своего маршрута, больница — не своя (сервер ответит 422) и
/// не заблокирована на этом маршруте (`progress.blockedMoCodes`: отказала или от неё отказались). Состояние маршрута
/// клиент не вычисляет — только читает `allowed`.
bool canRequestHere(PatientRoute? route, {required String? region, required String? profile, required String moCode}) {
  final progress = route?.progress;
  if (route == null || progress == null || !route.can(RouteCodes.actionRequestTransfer)) {
    return false;
  }
  return region == route.regionKato &&
      profile == route.organization.profileCode &&
      moCode != progress.originMoCode &&
      moCode != route.organization.moCode &&
      !progress.blockedMoCodes.contains(moCode);
}

/// По больнице [moCode] открыта просьба гражданина (`route.openRequest`) — чип «Запрос отправлен» вместо действия.
/// Только в списке региона и профиля своего маршрута: та же больница в чужом профиле — не та просьба.
bool requestedHere(PatientRoute? route, {required String? region, required String? profile, required String moCode}) =>
    route != null && region == route.regionKato && profile == route.organization.profileCode && route.openRequest?.toMoCode == moCode;
