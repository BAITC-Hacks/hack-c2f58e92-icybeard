import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';

/// Шесть ячеек кода по доске M-Auth-OTP (48×56, inset-фон, 24/500 табличными цифрами, текущая ячейка — обводка
/// 2 px accent, при ошибке — critical). Под ячейками одно настоящее поле ввода: цифры сами переходят в следующую
/// ячейку, стирание возвращает назад, вставка «123 456» или SMS-автозаполнение раскладывается по ячейкам.
class OtpField extends StatefulWidget {
  const OtpField({super.key, required this.controller, required this.label, this.length = 6, this.onCompleted, this.hasError = false, this.enabled = true, this.autofocus = true});

  final TextEditingController controller;

  /// Подпись для чтения с экрана («Код из 6 цифр»).
  final String label;
  final int length;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(OtpField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onChanged(String value) {
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final active = _focus.hasFocus ? text.length.clamp(0, widget.length - 1) : -1;
    return Stack(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _Cell(digit: i < text.length ? text[i] : '', active: i == active, error: widget.hasError)),
              ],
            ],
          ),
        ),
        // Настоящее поле поверх ячеек: прозрачный текст и курсор, тап по любой ячейке открывает клавиатуру.
        Positioned.fill(
          child: Semantics(
            label: widget.label,
            textField: true,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              // поле растянуто на все ячейки, чтобы тап по любой открывал клавиатуру
              expands: true,
              maxLines: null,
              minLines: null,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.length)],
              onChanged: _onChanged,
              onSubmitted: (value) => value.length == widget.length ? widget.onCompleted?.call(value) : null,
              showCursor: false,
              style: const TextStyle(color: ColorTokens.transparent, fontSize: 1),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.digit, required this.active, required this.error});

  final String digit;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ring = error ? colors.danger : colors.accent;
    return AnimatedContainer(
      duration: AppDurations.fast,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.neutralSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: active || (error && digit.isNotEmpty) ? ring : ColorTokens.transparent, width: 2),
      ),
      child: Text(digit, style: Theme.of(context).textTheme.headlineSmall?.merge(AppType.numeric)),
    );
  }
}
