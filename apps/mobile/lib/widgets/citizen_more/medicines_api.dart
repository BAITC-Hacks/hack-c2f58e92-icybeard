import '../../api/client.dart';
import '../../api/models.dart';

/// «Проверка рецепта» целиком: `CheckResponse` клиента не разбирает долю обеспеченности похожих МНН
/// (`shortage.peerRatio`) и «Другие МНН при этой нозологии» (`alternatives`), которые показывает веб
/// (`MedicinesView.vue`). Тот же `POST /medicines/check` поверх публичного `post` (слой API заморожен) — заявка на
/// перенос полей в `CheckResponse` в отчёте.
extension MedicinesApi on ApiClient {
  /// Проверка МНН [mnnId] (или только нозологии [nosologyId]) в регионе [regionKato]; без региона — вся страна.
  Future<MedicineCheck> checkMedicineDetails({String? mnnId, String? nosologyId, String? regionKato}) async {
    final json = await post('/api/v1/medicines/check', {'mnnId': mnnId, 'nosologyId': nosologyId, 'regionKato': regionKato}) as Map<String, dynamic>;
    final shortage = json['shortage'] as Map<String, dynamic>? ?? const {};
    final others = json['alternatives'];
    return MedicineCheck(
      check: CheckResponse.fromJson(json),
      peerRatio: (shortage['peerRatio'] as num?)?.toDouble(),
      alternatives: List.unmodifiable(others is List<dynamic> ? others.whereType<Map<String, dynamic>>().map(OtherMnn.fromJson).where((m) => m.mnnId.isNotEmpty) : const <OtherMnn>[]),
    );
  }
}

/// Ответ проверки рецепта: [check] — разбор клиента, сверху — то, что клиент не разбирает.
class MedicineCheck {
  const MedicineCheck({required this.check, required this.alternatives, this.peerRatio});

  final CheckResponse check;

  /// Доля обеспеченных рецептов у похожих МНН той же категории (0…1); null — похожих с данными нет.
  final double? peerRatio;

  /// Другие МНН той же нозологии по объёму рецептов.
  final List<OtherMnn> alternatives;
}

/// МНН из «Другие МНН при этой нозологии»: тап выбирает его для проверки.
class OtherMnn {
  const OtherMnn({required this.mnnId, required this.name, required this.issued12m});

  final String mnnId;
  final String name;

  /// Рецептов за 12 месяцев.
  final int issued12m;

  factory OtherMnn.fromJson(Map<String, dynamic> json) => OtherMnn(
        mnnId: json['mnnId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        issued12m: (json['issued12m'] as num?)?.toInt() ?? 0,
      );
}
