import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';

/// Открывает адрес во внешнем браузере (веб-кабинет, регистрация организации, действия Keycloak). Если браузера нет
/// или адрес не открылся — сообщение внизу экрана, приложение не падает.
Future<void> openExternal(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = S.at(context).linkUnavailable;
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }
}
