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
  final List<AdaptiveNavigationDestination>? mobileDestinations;

  const AdaptiveLayout({
    super.key,
    required this.body,
    this.desktopBody,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.destinations,
    this.mobileDestinations,
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
      if (offset <= 10 && !_showBottomBar) {
        setState(() => _showBottomBar = true);
      }
      if (notification is ScrollStartNotification) {
        _lastOffset = offset;
      } else if (notification is UserScrollNotification) {
        if (notification.direction == ScrollDirection.reverse &&
            _showBottomBar) {
          setState(() => _showBottomBar = false);
        } else if (notification.direction == ScrollDirection.forward &&
            !_showBottomBar) {
          setState(() => _showBottomBar = true);
        }
        _lastOffset = offset;
      }
      if (offset <= 0 && !_showBottomBar) {
        setState(() => _showBottomBar = true);
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

    final mobileDestinations = widget.mobileDestinations ?? widget.destinations;

    final safeIndex = mobileDestinations.isEmpty
        ? 0
        : widget.currentIndex.clamp(0, mobileDestinations.length - 1);

    final bottomBar = SafeArea(
      top: false,
      child: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: widget.onNavigationChanged,
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurfaceVariant,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: mobileDestinations.map((d) {
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
        final isTablet =
            constraints.maxWidth >= 600 && constraints.maxWidth < 900;
        if (isDesktop || isTablet) {
          final theme = Theme.of(context);
          return Scaffold(
            key: widget.scaffoldKey,
            appBar: widget.appBar,
            drawer: widget.drawer,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IntrinsicWidth(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height,
                    child: NavigationRail(
                      selectedIndex: widget.currentIndex,
                      onDestinationSelected: widget.onNavigationChanged,
                      labelType: NavigationRailLabelType.all,
                      minWidth: 72,
                      minExtendedWidth: 160,
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
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1200 : 800,
                    ),
                    child: isDesktop && widget.desktopBody != null
                        ? widget.desktopBody!
                        : widget.body,
                  ),
                ),
              ],
            ),
          );
        }

        final theme = Theme.of(context);
        Widget body = widget.body;
        if (widget.onRefresh != null) {
          body = RefreshIndicator(
            onRefresh: widget.onRefresh!,
            color: theme.colorScheme.primary,
            child: widget.body,
          );
        }

        Widget scrollable = NestedScrollView(
          controller: widget.scrollController,
          floatHeaderSlivers: true,
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            final bar = widget.appBar is AppBar
                ? widget.appBar as AppBar
                : null;
            return <Widget>[
              if (widget.appBar != null)
                SliverAppBar(
                  leading: bar?.leading,
                  title: bar?.title,
                  actions: bar?.actions,
                  centerTitle: bar?.centerTitle ?? true,
                  backgroundColor:
                      bar?.backgroundColor ?? theme.colorScheme.surface,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  floating: true,
                  snap: true,
                  pinned: false,
                  forceElevated: innerBoxIsScrolled,
                ),
            ];
          },
          body: body,
        );

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
