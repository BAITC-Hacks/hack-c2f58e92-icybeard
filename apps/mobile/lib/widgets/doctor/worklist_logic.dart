import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../format.dart';
import '../status_chip.dart';

/// Правила показа рабочего списка врача — как в вебе (WorklistView.vue): главный чип строки, счётчики для фильтра,
/// фильтр по одному флагу, поиск по номеру и сортировка по колонкам. Флаги, приоритет и следующий шаг считает сервер;
/// здесь только выбор того, что показать, и порядок строк. Чистые функции: входные списки не меняются.

/// Пункт фильтра «Все пациенты».
const worklistFilterAll = 'all';

/// Порядок флагов для главного чипа строки: первый найденный из этого списка (веб `primaryFlag`).
const worklistChipOrder = [
  RouteCodes.flagDateOverdue,
  RouteCodes.patientSignalFlag,
  RouteCodes.flagTransferPending,
  RouteCodes.flagTransferredIn,
  RouteCodes.flagRefusalRisk,
  RouteCodes.flagFasterAlternative,
  RouteCodes.flagStuckOver30,
  RouteCodes.flagPrefersCurrent,
];

/// Тон чипа флага (веб `FLAG_TONES`): риск отказа и прошедшая дата — danger, запрос пациента — warn, «есть быстрее»
/// и переводы — accent, остальное и незнакомое — neutral. Те же тоны у чипов на маршруте пациента.
StatusTone worklistFlagTone(String flag) => switch (flag) {
      RouteCodes.flagRefusalRisk || RouteCodes.flagDateOverdue => StatusTone.danger,
      RouteCodes.patientSignalFlag => StatusTone.warn,
      RouteCodes.flagFasterAlternative || RouteCodes.flagTransferPending || RouteCodes.flagTransferredIn => StatusTone.accent,
      _ => StatusTone.neutral,
    };

/// Тон этапа строки без флагов (веб `STAGE_TONES`): зарегистрирован и вызов — ok, ожидает — accent.
StatusTone worklistStageTone(String stageCode) => switch (stageCode) {
      'registered' || 'called' => StatusTone.ok,
      'waiting' => StatusTone.accent,
      _ => StatusTone.neutral,
    };

/// Главный чип строки: первый известный флаг в порядке [worklistChipOrder], иначе этап (подпись API для незнакомого).
({String label, StatusTone tone}) worklistChip(S s, WorklistItem item) {
  final flag = worklistChipOrder.where(item.riskFlags.contains).firstOrNull;
  if (flag != null) {
    return (label: s.worklistFlag(flag), tone: worklistFlagTone(flag));
  }
  return (label: s.worklistStage(item.stageCode, fallback: item.stage), tone: worklistStageTone(item.stageCode));
}

/// Счётчики для листа фильтра: «Все пациенты» и каждый из восьми флагов (нулевые тоже), в порядке пунктов.
Map<String, int> worklistCounts(List<WorklistItem> items) => {
      worklistFilterAll: items.length,
      for (final flag in RouteCodes.riskFlags) flag: items.where((i) => i.riskFlags.contains(flag)).length,
    };

/// Колонка сортировки (веб `SORT_COLUMNS`): номер, профиль, больница — текстовые; дни и приоритет — числовые.
enum WorklistSortKey {
  patient,
  profile,
  organization,
  days,
  priority;

  /// Числовая колонка: первый выбор сортирует по убыванию.
  bool get numeric => this == days || this == priority;
}

/// Выбранная сортировка: колонка и направление. По умолчанию — приоритет по убыванию.
@immutable
class WorklistSort {
  const WorklistSort(this.key, {required this.descending});

  static const initial = WorklistSort(WorklistSortKey.priority, descending: true);

  final WorklistSortKey key;
  final bool descending;

  /// Выбор колонки, как клик по заголовку в вебе: та же колонка — обратное направление; новая числовая — по
  /// убыванию, текстовая — по возрастанию.
  WorklistSort tap(WorklistSortKey next) => next == key ? WorklistSort(key, descending: !descending) : WorklistSort(next, descending: next.numeric);

  @override
  bool operator ==(Object other) => other is WorklistSort && other.key == key && other.descending == descending;

  @override
  int get hashCode => Object.hash(key, descending);
}

/// Видимые строки: фильтр по флагу [filter] (или все), поиск [query] — часть номера пациента без учёта регистра,
/// сортировка [sort]. Равные по ключу строки остаются в порядке сервера (приоритет ↓, дни ↓), как стабильная
/// сортировка веба. [profileName] — название профиля по коду для колонки «Профиль койки» (без него — код).
List<WorklistItem> visibleWorklist(
  List<WorklistItem> items, {
  String filter = worklistFilterAll,
  String query = '',
  WorklistSort sort = WorklistSort.initial,
  String Function(String profileCode)? profileName,
}) {
  final q = query.trim().toLowerCase();
  final rows = [
    for (final (index, item) in items.indexed)
      if ((filter == worklistFilterAll || item.riskFlags.contains(filter)) && (q.isEmpty || item.patientRef.toLowerCase().contains(q))) (index, item),
  ];
  final direction = sort.descending ? -1 : 1;
  rows.sort((a, b) {
    final byKey = _compare(sort.key, a.$2, b.$2, profileName) * direction;
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  return List.unmodifiable(rows.map((r) => r.$2));
}

int _compare(WorklistSortKey key, WorklistItem a, WorklistItem b, String Function(String)? profileName) => switch (key) {
      WorklistSortKey.patient => _text(a.patientRef).compareTo(_text(b.patientRef)),
      WorklistSortKey.profile => _text(profileName?.call(a.profileCode) ?? a.profileCode).compareTo(_text(profileName?.call(b.profileCode) ?? b.profileCode)),
      WorklistSortKey.organization => _text(shortOrgName(a.moName)).compareTo(_text(shortOrgName(b.moName))),
      WorklistSortKey.days => a.daysWaiting.compareTo(b.daysWaiting),
      WorklistSortKey.priority => a.priority.compareTo(b.priority),
    };

/// Ключ текстового сравнения: без регистра, «ё» рядом с «е» (как localeCompare веба для русского).
String _text(String value) => value.toLowerCase().replaceAll('ё', 'е');
