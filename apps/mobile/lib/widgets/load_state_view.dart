import 'package:flutter/material.dart';

import '../state/load_state.dart';
import 'state_view.dart';

/// Рисует состояние загрузки одинаково на всех экранах (доска W-States): скелетон, данные, пустое состояние,
/// ошибка с повтором; ответ API 403 — «Нет доступа».
class LoadStateView<T> extends StatelessWidget {
  const LoadStateView({
    super.key,
    required this.state,
    required this.skeleton,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
  });

  final LoadState<T> state;
  final Widget skeleton;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) => switch (state) {
        Loading<T>() => skeleton,
        Failed<T>(:final error) => ErrorState(error: error, onRetry: onRetry),
        Loaded<T>(:final data) => (isEmpty?.call(data) ?? false) ? (empty ?? const SizedBox.shrink()) : builder(context, data),
      };
}
