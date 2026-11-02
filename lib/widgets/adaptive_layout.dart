import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

class AdaptiveLayout extends StatefulWidget {
  final Widget body;
  final Widget? desktopBody;
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<AdaptiveNavigationDestination> destinations;
  final Widget? drawer;
  final PreferredSizeWidget? appBar;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final ScrollController? scrollController;
  final Future<void> Function()? onRefresh;

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
    this.scrollController,
    this.onRefresh,
  });

  @override
  State<AdaptiveLayout> createState() => _AdaptiveLayoutState();
}

class _AdaptiveLayoutState extends State<AdaptiveLayout> {
  bool _showBottomBar = true;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    _attachListener(widget.scrollController);
  }

  @override
  void didUpdateWidget(AdaptiveLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollController != oldWidget.scrollController) {
      _attachListener(widget.scrollController);
    }
  }

  void _attachListener(ScrollController? controller) {
    controller?.removeListener(_onScroll);
    controller?.addListener(_onScroll);
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null) return;
    final offset = controller.offset;
    if (offset > _lastOffset + 2) {
      if (_showBottomBar) setState(() => _showBottomBar = false);
    } else if (offset < _lastOffset - 2) {
      if (!_showBottomBar) setState(() => _showBottomBar = true);
    }
    _lastOffset = offset;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Pages are allowed to own their scroll view (Home currently uses an
    // inner SingleChildScrollView). Listening only to the controller passed
    // to this shell therefore misses the real Android/iOS scroll events.
    if (notification.depth == 0 || notification is UserScrollNotification) {
      final metrics = notification.metrics;
      final offset = metrics.pixels;
      if (notification is ScrollStartNotification) {
        _lastOffset = offset;
      } else if (notification is UserScrollNotification) {
        if (notification.direction == ScrollDirection.reverse && _showBottomBar) {
          setState(() => _showBottomBar = false);
        } else if (notification.direction == ScrollDirection.forward && !_showBottomBar) {
          setState(() => _showBottomBar = true);
        }
        _lastOffset = offset;
      }
    }
    return false;
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  Widget _buildMobileShell(BuildContext context, Widget scrollable) {
    final theme = Theme.of(context);

    final bottomBar = SafeArea(
      top: false,
      child: BottomNavigationBar(
        currentIndex: widget.currentIndex,
        onTap: widget.onNavigationChanged,
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurfaceVariant,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: widget.destinations.map((d) {
          return BottomNavigationBarItem(
            icon: Icon(d.icon),
            activeIcon: Icon(d.selectedIcon ?? d.icon),
            label: d.label,
          );
        }).toList(),
      ),
    );

    return Scaffold(
      key: widget.scaffoldKey,
      drawer: widget.drawer,
      extendBody: false,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: scrollable,
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: _showBottomBar ? bottomBar : const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
        if (isDesktop || isTablet) {
          final theme = Theme.of(context);
          return Scaffold(
            key: widget.scaffoldKey,
            appBar: widget.appBar,
            drawer: widget.drawer,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NavigationRail(
                  selectedIndex: widget.currentIndex,
                  onDestinationSelected: widget.onNavigationChanged,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 80,
                  selectedLabelTextStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  unselectedLabelTextStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  destinations: widget.destinations.map((d) {
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
                      child: isDesktop && widget.desktopBody != null ? widget.desktopBody! : widget.body,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        Widget scrollable = CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            if (widget.appBar != null)
                SliverAppBar(
                  leading: (widget.appBar as AppBar?)?.leading,
                  title: (widget.appBar as AppBar?)?.title,
                  actions: (widget.appBar as AppBar?)?.actions,
                  centerTitle: (widget.appBar as AppBar?)?.centerTitle ?? true,
                  elevation: 0,
                  floating: true,
                  pinned: false,
                ),
            SliverToBoxAdapter(child: widget.body),
          ],
        );

        if (widget.onRefresh != null) {
          scrollable = RefreshIndicator(
            onRefresh: widget.onRefresh!,
            color: const Color(0xFFC62828),
            child: scrollable,
          );
        }

        return _buildMobileShell(context, scrollable);
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
