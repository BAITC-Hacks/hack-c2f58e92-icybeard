import '../../api/client.dart';
import 'wait_logic.dart';

/// Справочники «Сколько ждут», которых нет в `ApiClient` в нужном виде (веб `WaitView.vue`): индекс доступности с
/// долей ожидавших дольше 30 дней и p90 (`IndexItem` клиента их не разбирает) и сезонность NHS
/// (`GET /refdata/seasonality`). Расширение поверх публичного `get` — заявка на перенос в `lib/api` в отчёте.
extension WaitApi on ApiClient {
  /// `GET /index?profileCode=` — регионы с индексом по профилю; число строк — «из {total} регионов».
  Future<List<RegionIndex>> waitIndex({required String profileCode}) async {
    final json = await get('/api/v1/index', {'profileCode': profileCode});
    final items = json is Map<String, dynamic> ? (json['items'] as List<dynamic>?) ?? const [] : const [];
    return List.unmodifiable(items.whereType<Map<String, dynamic>>().map(RegionIndex.fromJson));
  }

  /// `GET /refdata/seasonality` — множители по месяцам рядов NHS; подсказка берёт ряд листа ожидания.
  Future<List<SeasonPoint>> seasonality() async {
    final json = await get('/api/v1/refdata/seasonality');
    final items = json is Map<String, dynamic> ? (json['items'] as List<dynamic>?) ?? const [] : const [];
    return List.unmodifiable(items.whereType<Map<String, dynamic>>().map(SeasonPoint.fromJson));
  }
}

/// Строка индекса доступности (`GET /index`): место региона и из чего оно сложилось.
class RegionIndex {
  const RegionIndex({required this.regionKato, required this.name, required this.indexValue, required this.rank, this.shareOver30, this.p90Days});

  final String regionKato;
  final String name;

  /// 0…100: 100 — регион, где ждут меньше всего.
  final double indexValue;
  final int rank;

  /// Доля пациентов, ждавших дольше 30 дней (0…1).
  final double? shareOver30;

  /// Сколько ждали самые долгие 10 % пациентов, дн.
  final double? p90Days;

  factory RegionIndex.fromJson(Map<String, dynamic> json) => RegionIndex(
        regionKato: json['regionKato'] as String? ?? '',
        name: json['name'] as String? ?? '',
        indexValue: (json['indexValue'] as num?)?.toDouble() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        shareOver30: (json['shareOver30'] as num?)?.toDouble(),
        p90Days: (json['p90Days'] as num?)?.toDouble(),
      );
}
