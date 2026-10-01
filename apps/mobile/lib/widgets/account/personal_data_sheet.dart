import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../l10n/strings.dart';
import '../../state/load_state.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../api_error.dart';
import '../app_card.dart';
import '../error_box.dart';
import '../picker_sheet.dart';
import '../skeleton.dart';
import '../state_view.dart';
import '../status_chip.dart';
import 'account_api.dart';

/// Лист «Личные данные» из профиля (веб `ProfileView.vue`, P-2…P-5): ФИО (и у сотрудника должность, специальность)
/// только для чтения, телефон с проверкой «+7 и 10 цифр», рабочая почта со статусом подтверждения, часовой пояс.
/// «Сохранить изменения» — `PUT /me/profile`; язык профиля уходит обратно как пришёл (решение Q11: язык интерфейса —
/// настройка устройства). true — сохранено (экран показывает «Сохранено»).
Future<bool> showPersonalDataSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PersonalDataSheet(),
    ) ??
    false;

class _PersonalDataSheet extends StatefulWidget {
  const _PersonalDataSheet();

  @override
  State<_PersonalDataSheet> createState() => _PersonalDataSheetState();
}

class _PersonalDataSheetState extends State<_PersonalDataSheet> {
  final _phone = TextEditingController();
  LoadState<AccountProfile> _state = const Loading();
  String _timeZone = AccountProfile.defaultTimeZone;
  bool _saving = false;
  String? _phoneError;
  String? _timeZoneError;
  Object? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<Session>().api;

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final profile = await _api.myProfile();
      if (!mounted) {
        return;
      }
      _phone.text = formatKzPhone(profile.phone ?? '');
      setState(() {
        _timeZone = profile.timeZone;
        _state = Loaded(profile);
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  bool get _phoneValid => _phone.text.trim().isEmpty || isKzPhone(_phone.text);

  bool _dirty(AccountProfile profile) => normalizedPhone(_phone.text) != normalizedPhone(profile.phone ?? '') || _timeZone != profile.timeZone;

  Future<void> _pickTimeZone() async {
    final s = S.at(context);
    final zones = [if (!kzTimeZones.contains(_timeZone)) _timeZone, ...kzTimeZones];
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.timeZoneField,
      items: [for (final z in zones) PickerItem(z, timeZoneCity(z))],
      selected: _timeZone,
      search: false,
    );
    if (chosen != null && mounted) {
      setState(() {
        _timeZone = chosen;
        _timeZoneError = null;
      });
    }
  }

  Future<void> _save(AccountProfile profile) async {
    setState(() {
      _saving = true;
      _saveError = null;
      _phoneError = null;
      _timeZoneError = null;
    });
    try {
      await _api.saveProfile(phone: normalizedPhone(_phone.text), language: profile.language, timeZone: _timeZone);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      final phone = apiFieldError(e, 'phone');
      final zone = apiFieldError(e, 'timeZone');
      setState(() {
        _phoneError = phone;
        _timeZoneError = zone;
        _saveError = phone == null && zone == null ? e : null;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final state = _state;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(s.personalTitle),
          const SizedBox(height: AppSpacing.lg),
          switch (state) {
            Loading<AccountProfile>() => const Column(children: [Skeleton(height: 44), SizedBox(height: AppSpacing.md), Skeleton(height: 44), SizedBox(height: AppSpacing.md), Skeleton(height: 44)]),
            Failed<AccountProfile>(:final error) => ErrorState(error: error, onRetry: _load, compact: true),
            Loaded<AccountProfile>(:final data) => _form(s, data),
          },
        ],
      ),
    );
  }

  Widget _form(S s, AccountProfile profile) {
    final theme = Theme.of(context);
    final verified = context.read<Session>().me?.emailVerified;
    final phoneError = _phoneError ?? (_phoneValid ? null : s.phoneInvalid);
    final canSave = !_saving && _phoneValid && _dirty(profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadOnly(label: s.fullNameField, value: profile.displayName),
        if (profile.hasJob) ...[
          _ReadOnly(label: s.positionField, value: profile.position ?? '—'),
          _ReadOnly(label: s.specialtyField, value: profile.specialty ?? '—'),
          Text(s.jobByAdminNote, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.lg),
        ],
        FieldLabel(s.phoneField),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          onChanged: (_) => setState(() => _phoneError = null),
          decoration: InputDecoration(hintText: s.phoneHint, errorText: phoneError, errorMaxLines: 3),
        ),
        const SizedBox(height: AppSpacing.lg),
        FieldLabel(s.workEmail),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(profile.email ?? context.read<Session>().email ?? '—', style: theme.textTheme.bodyMedium),
            if (verified != null) StatusChip(verified ? s.emailVerifiedChip : s.emailNotVerifiedChip, tone: verified ? StatusTone.ok : StatusTone.warn),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(s.emailByAdminNote, style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.lg),
        FieldLabel(s.timeZoneField),
        _SelectField(value: timeZoneCity(_timeZone), onTap: _saving ? null : _pickTimeZone, error: _timeZoneError),
        if (_saveError != null) ...[const SizedBox(height: AppSpacing.lg), ErrorBox(error: _saveError)],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(onPressed: canSave ? () => _save(profile) : null, child: Text(s.saveChanges)),
      ],
    );
  }
}

/// Поле только для чтения: kicker и значение.
class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [FieldLabel(label), Text(value, style: Theme.of(context).textTheme.bodyLarge)],
        ),
      );
}

/// Поле выбора 48 px с рамкой, как у полей ввода: значение и «⌄»; ошибка сервера — строкой ниже.
class _SelectField extends StatelessWidget {
  const _SelectField({required this.value, required this.onTap, this.error});

  final String value;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: error == null ? colors.hairline : colors.danger, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSizes.select),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(value, style: theme.textTheme.bodyLarge)),
                  Icon(Icons.expand_more, size: 20, color: colors.muted),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[const SizedBox(height: AppSpacing.xs), Text(error!, style: theme.textTheme.labelSmall?.copyWith(color: colors.danger))],
      ],
    );
  }
}
