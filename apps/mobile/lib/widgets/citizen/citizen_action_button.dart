import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/citizen_route_controller.dart';
import '../../theme/app_theme.dart';

/// Вид кнопки действия гражданина: primary (синяя), secondary (accent-subtle), ссылка, опасное (danger-soft).
enum CitizenButtonKind { primary, secondary, link, danger }

/// Кнопка действия по маршруту: пока любое действие гражданина в полёте ([CitizenRouteController.isActing]), все
/// такие кнопки заблокированы — двойное нажатие не пишет две записи журнала; спиннер — только у той, что нажата.
/// [onPressed] — весь сценарий нажатия (лист подтверждения, запрос, сообщение); кнопка заблокирована и на время
/// листа. Ширина — во всю строку, кроме ссылки и [compact].
class CitizenActionButton extends StatefulWidget {
  const CitizenActionButton({super.key, required this.label, required this.onPressed, this.kind = CitizenButtonKind.primary, this.icon, this.compact = false});

  final String label;
  final Future<void> Function() onPressed;
  final CitizenButtonKind kind;
  final IconData? icon;

  /// Малая кнопка по ширине текста (блок «Не хотите переводиться?», плитки).
  final bool compact;

  @override
  State<CitizenActionButton> createState() => _CitizenActionButtonState();
}

class _CitizenActionButtonState extends State<CitizenActionButton> {
  var _pressed = false;

  Future<void> _run() async {
    setState(() => _pressed = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _pressed = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<CitizenRouteController?, bool>((c) => c?.isActing ?? false);
    final spinning = _pressed && busy;
    final onPressed = busy || _pressed ? null : _run;
    final icon = spinning
        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : (widget.icon == null ? null : Icon(widget.icon, size: 18));
    final label = Text(widget.label, textAlign: TextAlign.center);
    final small = widget.compact ? AppButtons.small(context) : null;
    final button = switch (widget.kind) {
      CitizenButtonKind.primary => FilledButton.icon(style: small, onPressed: onPressed, icon: icon, label: label),
      CitizenButtonKind.secondary => OutlinedButton.icon(style: small, onPressed: onPressed, icon: icon, label: label),
      CitizenButtonKind.danger => OutlinedButton.icon(style: AppButtons.danger(context, small: widget.compact), onPressed: onPressed, icon: icon, label: label),
      CitizenButtonKind.link => TextButton.icon(onPressed: onPressed, icon: icon, label: label),
    };
    if (widget.compact || widget.kind == CitizenButtonKind.link) {
      return Align(alignment: AlignmentDirectional.centerStart, child: button);
    }
    return button;
  }
}
