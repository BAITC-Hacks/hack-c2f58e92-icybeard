import 'dart:convert';

import 'package:darumen/api/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Публичные эндпоинты экранов гражданина в `ApiClient` (без роутера и сессии): `POST /medicines/check` целиком (доля
/// похожих МНН и другие МНН нозологии), `GET /index` с долей ожидавших дольше 30 дней и p90,
/// `GET /refdata/seasonality`, текст памятки `GET /scribe/leaflets/{token}`.
void main() {
  late List<http.Request> requests;

  ApiClient client(Object? Function(http.Request request) reply) {
    requests = [];
    return ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        requests.add(request);
        final body = reply(request);
        return body is http.Response ? body : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  }

  const check = {
    'covered': true,
    'program': 'ГОБМП',
    'category': '63',
    'fillDaysP50': 4.2,
    'fillDaysP90': 11.0,
    'fillDaysP50Model': null,
    'pFilled14d': 0.87,
    'shortage': {'flag': false, 'score': 0.4, 'basis': 'доля обеспеченных за 4 недели в норме', 'peerRatio': 0.93, 'peerBasis': '12 МНН категории'},
    'pharmacies': <Object?>[],
    'alternatives': [
      {'mnnId': '1203', 'name': 'МНН 1203', 'issued12m': 15234},
      {'mnnId': '88', 'name': 'МНН 88', 'issued12m': 900},
    ],
    'basis': 'медиана и 90-й перцентиль по рецептам за 12 месяцев',
    'model': {'name': 'rx-fill', 'version': '1.0', 'trainedThrough': '2026-09-28'},
  };

  group('medicines check', () {
    test('POST /medicines/check gives the base response, the peer ratio and the other МНН', () async {
      final api = client((_) => check);
      final result = await api.checkMedicine(mnnId: '1201', nosologyId: '9', regionKato: '75');
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/medicines/check');
      expect(jsonDecode(requests.single.body), {'mnnId': '1201', 'nosologyId': '9', 'regionKato': '75'});
      expect(result.covered, isTrue);
      expect(result.fillDaysP50, 4.2);
      expect(result.shortage.peerRatio, 0.93);
      expect(result.alternatives.map((a) => a.mnnId), ['1203', '88']);
      expect(result.alternatives.first.name, 'МНН 1203');
      expect(result.alternatives.first.issued12m, 15234);
    });

    test('without the peer ratio and the list the extras are empty, the whole country sends no region', () async {
      final api = client((_) => {...check, 'shortage': {'flag': true, 'score': 2.1, 'basis': ''}, 'alternatives': null});
      final result = await api.checkMedicine(nosologyId: '9');
      expect(jsonDecode(requests.single.body), {'mnnId': null, 'nosologyId': '9', 'regionKato': null});
      expect(result.shortage.peerRatio, isNull);
      expect(result.alternatives, isEmpty);
      expect(result.shortage.flag, isTrue);
    });
  });

  group('wait refdata', () {
    test('GET /index keeps the share over 30 days and p90 for the explanation', () async {
      final api = client((_) => {
            'items': [
              {'regionKato': '75', 'name': 'г. Алматы', 'shareOver30': 0.42, 'p90Days': 98, 'indexValue': 51.3, 'rank': 7, 'n': 300},
              {'regionKato': '71', 'name': 'г. Астана'},
            ],
          });
      final items = await api.regionIndex(profileCode: '121');
      expect(requests.single.url.queryParameters, {'profileCode': '121'});
      expect(items.first.shareOver30, 0.42);
      expect(items.first.p90Days, 98);
      expect(items.first.rank, 7);
      expect(items.last.shareOver30, isNull);
      expect(items.last.indexValue, 0);
    });

    test('GET /refdata/seasonality parses the monthly multipliers', () async {
      final api = client((_) => {
            'items': [
              {'seriesId': 'rtt_waiting_list', 'month': 1, 'multiplier': 0.9473, 'title': 'RTT'},
            ],
          });
      final points = await api.seasonality();
      expect(requests.single.url.path, '/api/v1/refdata/seasonality');
      expect(points.single.seriesId, 'rtt_waiting_list');
      expect(points.single.month, 1);
      expect(points.single.multiplier, 0.9473);
    });

    test('an error of the API is an ApiException', () async {
      final api = client((_) => http.Response(jsonEncode({'title': 'Not found'}), 404, headers: {'content-type': 'application/problem+json'}));
      await expectLater(api.regionIndex(profileCode: '1'), throwsA(isA<ApiException>()));
    });
  });

  group('leaflet', () {
    test('GET /scribe/leaflets/{token} escapes the token and parses the text; missing fields are empty', () async {
      final api = client((_) => {'text': 'Что дальше', 'language': 'kk', 'approvedAt': '2026-10-01T09:30:00+00:00'});
      final leaflet = await api.publicLeaflet('a/b');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/v1/scribe/leaflets/a%2Fb');
      expect(leaflet.text, 'Что дальше');
      expect(leaflet.language, 'kk');
      expect(leaflet.approvedAt, '2026-10-01T09:30:00+00:00');
      final bare = await client((_) => {'text': 'x'}).publicLeaflet('t');
      expect(bare.language, isEmpty);
      expect(bare.approvedAt, isEmpty);
    });
  });
}
