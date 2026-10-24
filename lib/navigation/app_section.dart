import 'package:flutter/material.dart';

enum AppSection {
  home('الرئيسية', Icons.home_outlined, Icons.home),
  quran('القرآن', Icons.menu_book_outlined, Icons.menu_book),
  adhkar('الأذكار', Icons.eco_outlined, Icons.eco),
  qibla('القبلة', Icons.explore_outlined, Icons.explore),
  more('المزيد', Icons.more_horiz, Icons.more_horiz);

  const AppSection(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}
