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
      oldWidget.scrollController?.removeListener(_onScroll);
      _attachListener(widget.scrollController);
    }
  }

  void _attachListener(ScrollController? controller) {
    controller?.removeListener(_onScroll);
    controller?.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;

    final offset = controller.offset;

    if (offset > _lastOffset + 2) {
      if (_showBottomBar) {
        setState(() => _showBottomBar = false);
      }
    } else if (offset < _lastOffset - 2) {
      if (!_showBottomBar) {
        setState(() => _showBottomBar = true);
      }
    }

    _lastOffset = offset;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (!mounted) return false;
    if (notification.depth == 0 || notification is UserScrollNotification) {
      final offset = notification.metrics.pixels;

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

  // ---------------------------------------------------------------------------
  // MOBILE LAYOUT
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // DESKTOP / TABLET NAVIGATION RAIL
  // ---------------------------------------------------------------------------

  Widget _buildNavigationRail(BuildContext context, double availableHeight) {
    final theme = Theme.of(context);

    final railHeight = availableHeight.isFinite
        ? availableHeight
        : MediaQuery.of(context).size.height;

    final destinations = widget.destinations;

    if (destinations.isEmpty) {
      return const SizedBox(width: 72);
    }

    final selectedIndex = widget.currentIndex.clamp(0, destinations.length - 1);

    // We use IntrinsicWidth so the rail grows to fit the longest text.
    // We wrap it in a Container to apply the background color seamlessly.
    return Container(
      height: railHeight,
      color: theme.colorScheme.surface, // Match background to main app
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: railHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8), // Top padding
                ...List.generate(destinations.length, (index) {
                  final destination = destinations[index];
                  final selected = index == selectedIndex;

                  // Determine colors based on selection
                  final activeColor = theme.colorScheme.primary;
                  final inactiveColor = theme.colorScheme.onSurfaceVariant;
                  final iconColor = selected ? activeColor : inactiveColor;
                  final textColor = selected ? activeColor : inactiveColor;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Material(
                      color: selected
                          ? theme.colorScheme.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => widget.onNavigationChanged(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                selected
                                    ? destination.selectedIcon ??
                                          destination.icon
                                    : destination.icon,
                                size: 24,
                                color: iconColor,
                              ),
                              const SizedBox(width: 16),
                              // Text is allowed to take required space without wrapping
                              Text(
                                destination.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: textColor,
                                ),
                              ),
                              // Add some right padding so text doesn't touch the edge
                              const SizedBox(width: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8), // Bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN RESPONSIVE LAYOUT
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isTablet =
            constraints.maxWidth >= 600 && constraints.maxWidth < 900;

        if (isDesktop || isTablet) {
          final theme = Theme.of(context);

          // Use the actual available height instead of the full screen height.
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.of(context).size.height;

          return Scaffold(
            key: widget.scaffoldKey,
            appBar: widget.appBar,
            drawer: widget.drawer,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNavigationRail(context, availableHeight),

                VerticalDivider(
                  thickness: 1,
                  width: 1,
                  color: theme.dividerColor,
                ),

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

        // ---------------------------------------------------------------------
        // MOBILE
        // ---------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// NAVIGATION DESTINATION MODEL
// -----------------------------------------------------------------------------

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
