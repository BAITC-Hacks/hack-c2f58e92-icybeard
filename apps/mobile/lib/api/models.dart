/// Модели ответов REST API Darumen (docs/api.md). Только то, что нужно мобильным экранам.
class ModelInfo {
  const ModelInfo({required this.name, required this.version, required this.trainedThrough});
  final String name;
  final String version;
  final String trainedThrough;
  factory ModelInfo.fromJson(Map<String, dynamic> json) =>
      ModelInfo(name: json['name'] as String? ?? '', version: json['version'] as String? ?? '', trainedThrough: json['trainedThrough'] as String? ?? '');
}

class Factor {
  const Factor({required this.name, required this.contribution, required this.text});
  final String name;
  final double contribution;
  final String text;
  factory Factor.fromJson(Map<String, dynamic> json) =>
      Factor(name: json['name'] as String, contribution: (json['contribution'] as num).toDouble(), text: json['text'] as String);
}

class Explanation {
  const Explanation({required this.summary, required this.factors});
  final String summary;
  final List<Factor> factors;
  factory Explanation.fromJson(Map<String, dynamic> json) => Explanation(
        summary: json['summary'] as String? ?? '',
        factors: (json['factors'] as List<dynamic>? ?? []).map((f) => Factor.fromJson(f as Map<String, dynamic>)).toList(),
      );
}

class QueueSnapshot {
  const QueueSnapshot({required this.len, this.ageP50, required this.throughputPerDay});
  final int len;
  final double? ageP50;
  final double throughputPerDay;
  factory QueueSnapshot.fromJson(Map<String, dynamic> json) => QueueSnapshot(
        len: (json['len'] as num).toInt(),
        ageP50: (json['ageP50'] as num?)?.toDouble(),
        throughputPerDay: (json['throughputPerDay'] as num).toDouble(),
      );
}

class PredictResponse {
  const PredictResponse({
    required this.p50Days,
    required this.p90Days,
    required this.pWithin30Days,
    required this.pRefusal,
    this.queue,
    required this.explanation,
    required this.model,
  });
  final double p50Days;
  final double p90Days;
  final double pWithin30Days;
  final double pRefusal;
  final QueueSnapshot? queue;
  final Explanation explanation;
  final ModelInfo model;
  factory PredictResponse.fromJson(Map<String, dynamic> json) => PredictResponse(
        p50Days: (json['p50Days'] as num).toDouble(),
        p90Days: (json['p90Days'] as num).toDouble(),
        pWithin30Days: (json['pWithin30Days'] as num).toDouble(),
        pRefusal: (json['pRefusal'] as num).toDouble(),
        queue: json['queue'] == null ? null : QueueSnapshot.fromJson(json['queue'] as Map<String, dynamic>),
        explanation: Explanation.fromJson(json['explanation'] as Map<String, dynamic>),
        model: ModelInfo.fromJson(json['model'] as Map<String, dynamic>),
      );
}

class Alternative {
  const Alternative({required this.moCode, required this.name, required this.p50Days, required this.p90Days, required this.pRefusal, required this.distanceKm});
  final String moCode;
  final String name;
  final double p50Days;
  final double p90Days;
  final double pRefusal;
  final double distanceKm;
  factory Alternative.fromJson(Map<String, dynamic> json) {
    final mo = json['mo'] as Map<String, dynamic>;
    return Alternative(
      moCode: mo['moCode'] as String,
      name: mo['name'] as String,
      p50Days: (json['p50Days'] as num).toDouble(),
      p90Days: (json['p90Days'] as num).toDouble(),
      pRefusal: (json['pRefusal'] as num).toDouble(),
      distanceKm: (json['distanceKm'] as num).toDouble(),
    );
  }
}

class Region {
  const Region({required this.kato, required this.name});
  final String kato;
  final String name;
  factory Region.fromJson(Map<String, dynamic> json) => Region(kato: json['regionKato'] as String, name: json['name'] as String);
}

class BedProfile {
  const BedProfile({required this.code, required this.name});
  final String code;
  final String name;
  factory BedProfile.fromJson(Map<String, dynamic> json) => BedProfile(code: json['profileCode'] as String, name: json['name'] as String);
}

class Organization {
  const Organization({required this.moCode, required this.name});
  final String moCode;
  final String name;
  factory Organization.fromJson(Map<String, dynamic> json) => Organization(moCode: json['moCode'] as String, name: json['name'] as String);
}

class IndexItem {
  const IndexItem({required this.regionKato, required this.name, required this.indexValue, required this.rank});
  final String regionKato;
  final String name;
  final double indexValue;
  final int rank;
  factory IndexItem.fromJson(Map<String, dynamic> json) => IndexItem(
        regionKato: json['regionKato'] as String,
        name: json['name'] as String,
        indexValue: (json['indexValue'] as num).toDouble(),
        rank: (json['rank'] as num).toInt(),
      );
}

class WorklistItem {
  const WorklistItem({
    required this.patientRef,
    required this.stage,
    required this.expectedDate,
    required this.riskFlags,
    required this.priority,
    required this.nextAction,
    required this.explanation,
    required this.moCode,
    required this.moName,
    required this.profileCode,
    required this.daysWaiting,
  });
  final String patientRef;
  final String stage;
  final String? expectedDate;
  final List<String> riskFlags;
  final int priority;
  final String nextAction;
  final String explanation;
  final String moCode;
  final String moName;
  final String profileCode;
  final int daysWaiting;
  factory WorklistItem.fromJson(Map<String, dynamic> json) => WorklistItem(
        patientRef: json['patientRef'] as String,
        stage: json['stage'] as String,
        expectedDate: json['expectedDate'] as String?,
        riskFlags: (json['riskFlags'] as List<dynamic>? ?? []).cast<String>(),
        priority: (json['priority'] as num).toInt(),
        nextAction: json['nextAction'] as String,
        explanation: json['explanation'] as String,
        moCode: json['moCode'] as String,
        moName: json['moName'] as String? ?? json['moCode'] as String,
        profileCode: json['profileCode'] as String,
        daysWaiting: (json['daysWaiting'] as num).toInt(),
      );
}

class Shortage {
  const Shortage({required this.flag, required this.score, required this.basis});
  final bool flag;
  final double score;
  final String basis;
  factory Shortage.fromJson(Map<String, dynamic> json) =>
      Shortage(flag: json['flag'] as bool, score: (json['score'] as num).toDouble(), basis: json['basis'] as String? ?? '');
}

class CheckResponse {
  const CheckResponse({required this.covered, this.program, this.fillDaysP50, this.fillDaysP90, this.pFilled14d, required this.shortage, required this.basis});
  final bool covered;
  final String? program;
  final double? fillDaysP50;
  final double? fillDaysP90;
  final double? pFilled14d;
  final Shortage shortage;
  final String basis;
  factory CheckResponse.fromJson(Map<String, dynamic> json) => CheckResponse(
        covered: json['covered'] as bool,
        program: json['program'] as String?,
        fillDaysP50: (json['fillDaysP50'] as num?)?.toDouble(),
        fillDaysP90: (json['fillDaysP90'] as num?)?.toDouble(),
        pFilled14d: (json['pFilled14d'] as num?)?.toDouble(),
        shortage: Shortage.fromJson(json['shortage'] as Map<String, dynamic>),
        basis: json['basis'] as String? ?? '',
      );
}

class Nosology {
  const Nosology({required this.id, required this.issued12m});
  final String id;
  final int issued12m;
  factory Nosology.fromJson(Map<String, dynamic> json) => Nosology(id: json['nosologyId'] as String, issued12m: (json['issued12m'] as num).toInt());
}

class Mnn {
  const Mnn({required this.id, required this.issued12m});
  final String id;
  final int issued12m;
  factory Mnn.fromJson(Map<String, dynamic> json) => Mnn(id: json['mnnId'] as String, issued12m: (json['issued12m'] as num).toInt());
}
