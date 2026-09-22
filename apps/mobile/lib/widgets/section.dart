import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'origin_tag.dart';

/// Заголовок раздела с меткой происхождения справа.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.origin});

  final String text;
  final Origin? origin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
            if (origin != null) OriginTag(origin!),
          ],
        ),
      );
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.origin, required this.child});

  final String title;
  final Origin? origin;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [SectionTitle(title, origin: origin), child],
      );
}

/// Каркас экрана: AppBar, SafeArea, ListView с единым отступом 16 и pull-to-refresh при наличии onRefresh.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.actions, required this.children, this.onRefresh, this.bottom});

  final String title;
  final List<Widget>? actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: children,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
      bottomNavigationBar: bottom,
    );
  }
}
