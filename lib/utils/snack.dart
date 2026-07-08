import 'package:flutter/material.dart';

import 'app_i18n.dart';

extension AppSnack on BuildContext {
  void showSnack(String message) {
    ScaffoldMessenger.of(this)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(t(message))));
  }
}
