import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../status_chip.dart';

/// Тон согласия пациента на перевод (`patientConsent`), как CONSENT_TONES веба: согласился — ok, ждём ответа — warn,
/// отказался и незнакомое значение — нейтральный.
StatusTone consentTone(String consent) => switch (consent) {
      'accepted' => StatusTone.ok,
      'pending' => StatusTone.warn,
      _ => StatusTone.neutral,
    };

/// Чип согласия пациента на перевод: подпись `routeConsentState` по голосу (персоналу — «ждём согласия пациента» /
/// «пациент согласился» / «пациент отказался»; гражданину — «Врач предлагает перевод» / «Вы согласились на перевод» /
/// «Вы отказались от перевода»), тон — [consentTone]. Входящие направления принимающей больницы и ответ врача на
/// «Мой путь».
class ConsentChip extends StatelessWidget {
  const ConsentChip(this.consent, {super.key, required this.voice});

  /// `RouteDecision.patientConsent` / `IncomingReferral.patientConsent`: pending | accepted | declined.
  final String consent;
  final RouteVoice voice;

  @override
  Widget build(BuildContext context) => StatusChip(S.at(context).routeConsentState(consent, voice), tone: consentTone(consent));
}
