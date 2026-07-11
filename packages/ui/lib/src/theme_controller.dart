import 'package:flutter/material.dart';

import 'theme.dart';

/// App-wide theme selection (aligned with ZVBible theme ids).
final class ThemeController extends ChangeNotifier {
  String _id = ZvcommTheme.defaultId;

  String get id => _id;

  ZvPalette get palette => ZvcommTheme.byId(_id);

  ThemeData get themeData => palette.toThemeData();

  void setTheme(String id) {
    final next = ZvcommTheme.byId(id).id;
    if (next == _id) return;
    _id = next;
    notifyListeners();
  }

  void cycle() {
    final all = ZvcommTheme.all;
    final i = all.indexWhere((p) => p.id == _id);
    final next = all[(i + 1) % all.length];
    setTheme(next.id);
  }
}
