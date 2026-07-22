import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:private_cinema_ios/screens/home_screen.dart';
import 'package:private_cinema_ios/screens/all_movies_screen.dart';
import 'package:private_cinema_ios/screens/downloads_screen.dart';
import 'package:private_cinema_ios/screens/favorites_screen.dart';
import 'package:private_cinema_ios/screens/settings_screen.dart';
import 'package:private_cinema_ios/screens/live_tv_screen.dart';
import 'package:private_cinema_ios/theme/app_colors.dart';

class NavigationHolder extends StatefulWidget {
  const NavigationHolder({super.key});

  @override
  State<NavigationHolder> createState() => _NavigationHolderState();
}

class _NavigationHolderState extends State<NavigationHolder> {
  int _currentIndex = 0;

  List<Widget> get _screens => [
    HomeScreen(
      key: const ValueKey('home'),
      onSwitchTab: (index) {
        if (mounted) {
          setState(() {
            _currentIndex = index;
          });
        }
      },
    ),
    const AllMoviesScreen(key: ValueKey('search')),
    const LiveTvScreen(key: ValueKey('livetv')),
    const FavoritesScreen(key: ValueKey('favorites')),
    const SettingsScreen(key: ValueKey('settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CinemaTheme>(
      valueListenable: ThemeManager.notifier,
      builder: (context, currentTheme, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // Screens with transition
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.01),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    );
                  },
                  child: _screens[_currentIndex],
                ),
              ),
              
              // Floating Frosted Glass Bottom Navigation Bar
              Positioned(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom + 8
                    : 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildNavItem(0, Icons.home_rounded),
                          _buildNavItem(1, Icons.search_rounded),
                          _buildNavItem(2, Icons.live_tv_rounded),
                          _buildNavItem(3, Icons.favorite_rounded),
                          _buildNavItem(4, Icons.person_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.35),
          size: isSelected ? 28 : 24,
        ),
      ),
    );
  }
}
