import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../app_card.dart';
import 'scribe_flow.dart';

/// Карточка двух текстов приёма (веб: «Запись приёма | Памятка пациенту»): переключатель вкладок и одно поле на
/// вкладку. Запись приёма следует за стенограммой, пока врач её не правил; после правки и новой стенограммы —
/// «Стенограмма изменилась после вашей правки.» и «Подставить текст стенограммы». Памятка собрана из назначений на
/// языке приёма; после правки — «Собрать заново из стенограммы». Пока текста нет — «Здесь появится текст приёма…».
/// Внизу — что произойдёт при утверждении (кнопка «Утвердить и выдать памятку» — в нижней зоне экрана). [locked] —
/// поля только для чтения (идёт запись, обработка или утверждение).
class ScribeTextsCard extends StatefulWidget {
  const ScribeTextsCard({super.key, required this.flow, required this.locked});

  final ScribeFlow flow;
  final bool locked;

  @override
  State<ScribeTextsCard> createState() => _ScribeTextsCardState();
}

class _ScribeTextsCardState extends State<ScribeTextsCard> {
  static const _record = 'record';
  static const _leaflet = 'leaflet';

  String _tab = _record;
  late final _recordText = TextEditingController(text: widget.flow.recordText);
  late final _leafletText = TextEditingController(text: widget.flow.leaflet);

  @override
  void initState() {
    super.initState();
    widget.flow.addListener(_sync);
  }

  @override
  void didUpdateWidget(ScribeTextsCard old) {
    super.didUpdateWidget(old);
    if (old.flow != widget.flow) {
      old.flow.removeListener(_sync);
      widget.flow.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.flow.removeListener(_sync);
    _recordText.dispose();
    _leafletText.dispose();
    super.dispose();
  }

  /// Текст в поле меняется вслед за ScribeFlow (новая стенограмма, «подставить», «собрать заново»); набор врача
  /// уже совпадает с flow и поле не трогает.
  void _sync() {
    _replace(_recordText, widget.flow.recordText);
    _replace(_leafletText, widget.flow.leaflet);
  }

  static void _replace(TextEditingController controller, String text) {
    if (controller.text != text) {
      controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final flow = widget.flow;
    final empty = flow.segments.isEmpty && flow.recordText.isEmpty;
    final record = _tab == _record;
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: _record, label: Text(s.aiScribeRecordTitle, maxLines: 2, textAlign: TextAlign.center)),
              ButtonSegment(value: _leaflet, label: Text(s.scribeLeafletLabel, maxLines: 2, textAlign: TextAlign.center)),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (empty)
            Text(s.aiScribeNoRecord, style: theme.textTheme.bodySmall)
          else ...[
            Text(record ? s.aiScribeRecordHint : s.aiScribeLeafletHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: ValueKey(_tab),
              controller: record ? _recordText : _leafletText,
              readOnly: widget.locked,
              minLines: record ? 5 : 6,
              maxLines: 14,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: record ? s.aiScribeRecordTitle : s.scribeLeafletLabel, alignLabelWithHint: true),
              onChanged: record ? flow.editRecord : flow.editLeaflet,
            ),
            if (record && flow.transcriptChanged && !widget.locked) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(s.aiScribeTranscriptChanged, style: theme.textTheme.bodySmall?.copyWith(color: AppTones.of(context).warn.fg)),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: flow.replaceRecord, child: Text(s.aiScribeReplaceRecord))),
            ],
            if (!record && flow.leafletDirty && !widget.locked)
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: flow.rebuildLeaflet, child: Text(s.aiScribeRebuildLeaflet))),
            const SizedBox(height: AppSpacing.sm),
            Text(s.aiScribeApproveHint, style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}
