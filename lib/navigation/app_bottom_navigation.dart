import 'package:flutter/material.dart';

import 'app_section.dart';
import '../core/localization/app_localization.dart';

/// Lets overlays reserve space above bars hosted on root navigator routes.
class BottomNavigationRouteSettings extends RouteSettings {
  const BottomNavigationRouteSettings({super.name});
}

/// The same interactive bar for the main surface and settings routes.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.section,
    required this.onSelected,
  });

  final AppSection section;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: NavigationBar(
        key: const ValueKey('haq-bottom-navigation'),
        selectedIndex: section.index,
        height: 72,
        backgroundColor: dark
            ? const Color(0xF2132331)
            : const Color(0xF9FFFFFF),
        indicatorColor: Colors.transparent,
        onDestinationSelected: onSelected,
        destinations: [
          for (final destination in AppSection.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: context.tr(
                'nav.${destination.name}',
                fallback: destination.label,
              ),
            ),
        ],
      ),
    );
  }
}
