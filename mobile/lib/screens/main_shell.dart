import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'detection_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _screens = [
    DashboardScreen(),
    MapScreen(),
    DetectionScreen(),
    AlertsScreen(),
    ProfileScreen(),
  ];

  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    // Automatically run non-blocking /health check on startup with LAN fallback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final beforeUrl = ref.read(serverUrlProvider);
      final ok = await ref
          .read(backendConnectionProvider.notifier)
          .checkHealth(allowAutoFallback: true);
      if (!mounted) return;
      final afterUrl = ref.read(serverUrlProvider);
      if (ok && beforeUrl != afterUrl) {
        refreshAllFireWatchData(ref);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(navigationTabProvider);
    final unreadCount = ref.watch(unreadAlertsCountProvider);
    _visitedTabs.add(tabIndex);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: tabIndex,
        children: List.generate(
          _screens.length,
          (i) => _visitedTabs.contains(i)
              ? _screens[i]
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: _IosBlurredTabBar(
        currentIndex: tabIndex,
        unreadCount: unreadCount,
        onTap: (idx) {
          if (idx != tabIndex) {
            HapticFeedback.selectionClick();
            ref.read(navigationTabProvider.notifier).setTab(idx);
          }
        },
      ),
    );
  }
}

class _IosBlurredTabBar extends StatelessWidget {
  const _IosBlurredTabBar({
    required this.currentIndex,
    required this.unreadCount,
    required this.onTap,
  });

  final int currentIndex;
  final int unreadCount;
  final ValueChanged<int> onTap;

  static const _items = [
    _TabItemData(
      label: 'Home',
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
    ),
    _TabItemData(
      label: 'Map',
      icon: CupertinoIcons.map,
      activeIcon: CupertinoIcons.map_fill,
    ),
    _TabItemData(
      label: 'Cameras',
      icon: CupertinoIcons.videocam,
      activeIcon: CupertinoIcons.videocam_fill,
    ),
    _TabItemData(
      label: 'Incidents',
      icon: CupertinoIcons.bell,
      activeIcon: CupertinoIcons.bell_fill,
    ),
    _TabItemData(
      label: 'Settings',
      icon: CupertinoIcons.gear_alt,
      activeIcon: CupertinoIcons.gear_alt_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.88),
            border: const Border(
              top: BorderSide(color: AppColors.cardBorder, width: 0.5),
            ),
          ),
          padding: EdgeInsets.only(
            top: 6,
            bottom: bottomPadding > 0 ? bottomPadding : 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = index == currentIndex;
              final showBadge = index == 3 && unreadCount > 0;
              final iconColor =
                  selected ? AppColors.primaryGreen : AppColors.textSecondary;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 24,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              AppIcon(
                                selected ? item.activeIcon : item.icon,
                                size: 22,
                                color: iconColor,
                              ),
                              if (showBadge)
                                Positioned(
                                  right: -6,
                                  top: -3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.5,
                                      vertical: 1,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerRed,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppColors.background,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.iosFontFamily,
                            fontSize: 10.5,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: iconColor,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItemData {
  const _TabItemData({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
