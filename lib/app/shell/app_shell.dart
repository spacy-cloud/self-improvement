import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/design/design.dart';

/// The scaffold around the four tabs: the active tab fills the body (each tab
/// keeps its own navigation and scroll state) and [AppBottomNavBar] sits below.
///
/// The centre plus button is an action: it opens the plus menu as a modal
/// sheet over the current tab and, after a pick, pushes the target on top, so
/// leaving it (save or cancel) returns to the tab the user started from.
///
/// Android back from a tab other than Home first returns to Home; only from
/// Home the system takes over. (An open plus menu, a pushed sub page or a
/// dialog sit above this page and take the back press before it ever gets
/// here: modal, then sub page, then Home, then the system.)
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey _navigationKey = GlobalKey(debugLabel: 'app-navigation');
  bool _plusOpen = false;

  void _select(int index) {
    final shell = widget.navigationShell;
    // Tapping the selected tab again returns it to its root.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  Future<void> _openPlus() async {
    if (_plusOpen) {
      return;
    }
    final box = _navigationKey.currentContext?.findRenderObject();
    final navigationHeight = box is RenderBox ? box.size.height : 0.0;
    setState(() => _plusOpen = true);
    String? route;
    try {
      route = await showPlusSheet(context, bottomInset: navigationHeight);
    } finally {
      if (mounted) {
        setState(() => _plusOpen = false);
      }
    }
    if (route != null && mounted) {
      unawaited(context.push<void>(route));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final shell = widget.navigationShell;
    return PopScope<Object?>(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          shell.goBranch(0);
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: shell,
        bottomNavigationBar: AppBottomNavBar(
          key: _navigationKey,
          selectedIndex: shell.currentIndex,
          onSelected: _select,
          onPlusPressed: _openPlus,
          plusOpen: _plusOpen,
        ),
      ),
    );
  }
}
