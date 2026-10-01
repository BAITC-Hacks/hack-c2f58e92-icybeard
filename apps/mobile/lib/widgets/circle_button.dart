import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Круглая кнопка-иконка 40 px — «назад», «поиск», «закрыть», язык в шапке экрана. Фон surface-muted (#E8EEFA)
/// на всех досках m-* синей гаммы.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.label, this.onTap, this.child});

  final IconData icon;

  /// Подпись для чтения с экрана и tooltip.
  final String label;
  final VoidCallback? onTap;

  /// Вместо иконки — произвольное содержимое (текст «ҚАЗ»).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.neutralSoft,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: AppSizes.iconButton,
              height: AppSizes.iconButton,
              child: Center(child: child ?? Icon(icon, size: 20, color: colors.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка языка в шапке: показывает язык, на который переключит («ҚАЗ» в русском интерфейсе, «РУС» —
/// в казахском). Локаль хранится в сессии.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final locale = context.select<Session, String>((x) => x.locale);
    final next = locale == 'kk' ? 'ru' : 'kk';
    return CircleIconButton(
      icon: Icons.language,
      label: s.switchLanguage(next),
      onTap: () => context.read<Session>().setLocale(next),
      child: Text(
        next == 'kk' ? 'ҚАЗ' : 'РУС',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13.5, letterSpacing: 0),
      ),
    );
  }
}
