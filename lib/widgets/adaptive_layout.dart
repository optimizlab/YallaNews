import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdaptiveLayout extends StatelessWidget {
  final Widget body;
  final Widget? desktopBody;
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<AdaptiveNavigationDestination> destinations;
  final Widget? drawer;
  final PreferredSizeWidget? appBar;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const AdaptiveLayout({
    super.key,
    required this.body,
    this.desktopBody,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.destinations,
    this.drawer,
    this.appBar,
    this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
        final isMobile = constraints.maxWidth < 600;

        if (isDesktop || isTablet) {
          return Scaffold(
            key: scaffoldKey,
            appBar: appBar,
            drawer: drawer,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: onNavigationChanged,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 80,
                  selectedLabelTextStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  unselectedLabelTextStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  destinations: destinations.map((d) {
                    return NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon ?? d.icon),
                      label: Text(d.label),
                    );
                  }).toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : 800),
                      child: isDesktop && desktopBody != null ? desktopBody! : body,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          key: scaffoldKey,
          appBar: appBar,
          drawer: drawer,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: body,
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: onNavigationChanged,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: destinations.map((d) {
              return BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.selectedIcon ?? d.icon),
                label: d.label,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class AdaptiveNavigationDestination {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const AdaptiveNavigationDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}
