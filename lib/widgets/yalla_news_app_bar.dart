import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class YallaNewsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onLeadingPressed;
  final VoidCallback? onActionPressed;
  final IconData leadingIcon;
  final IconData actionIcon;
  final bool showBack;

  const YallaNewsAppBar({
    Key? key,
    this.title = 'يلا نيوز',
    this.onLeadingPressed,
    this.onActionPressed,
    this.leadingIcon = Icons.menu_rounded,
    this.actionIcon = Icons.menu_rounded,
    this.showBack = false,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      centerTitle: true,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              onPressed: onLeadingPressed ?? () => Navigator.pop(context),
            )
          : IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onLeadingPressed ?? () {},
            ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            'EN',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(actionIcon, color: Theme.of(context).colorScheme.onSurface),
          onPressed: onActionPressed ?? () {},
        ),
      ],
    );
  }
}
