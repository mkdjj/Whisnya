import 'package:flutter/material.dart';

import 'app_i18n.dart';

extension AppSnack on BuildContext {
  void showSnack(String message) {
    ScaffoldMessenger.of(this)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(t(message))));
  }

  Future<bool> tryAction(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) showSnack(error.toString());
      return false;
    }
  }
}
