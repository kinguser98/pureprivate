import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:private_cinema_ios/admin/config/theme.dart';
import 'package:private_cinema_ios/admin/providers/auth_provider.dart';
import 'package:private_cinema_ios/admin/utils/drawer_helper.dart';
import 'package:private_cinema_ios/admin/screens/splash/splash_screen.dart';
import 'package:private_cinema_ios/admin/screens/auth/login_screen.dart';
import 'package:private_cinema_ios/admin/screens/dashboard/dashboard_screen.dart';
import 'package:private_cinema_ios/admin/screens/movies/movies_screen.dart';
import 'package:private_cinema_ios/admin/screens/iptv/iptv_screen.dart';
import 'package:private_cinema_ios/admin/screens/add_movie/add_movie_screen.dart';
import 'package:private_cinema_ios/admin/screens/edit_movie/edit_movie_screen.dart';
import 'package:private_cinema_ios/admin/screens/languages/languages_screen.dart';
import 'package:private_cinema_ios/admin/screens/iptv_settings/iptv_settings_screen.dart';
import 'package:private_cinema_ios/admin/screens/app_settings/app_settings_screen.dart';
import 'package:private_cinema_ios/admin/screens/bulk_updater/bulk_updater_screen.dart';
import 'package:private_cinema_ios/admin/screens/streamtape/streamtape_screen.dart';
import 'package:private_cinema_ios/admin/screens/backups/backups_screen.dart';
import 'package:private_cinema_ios/admin/screens/account_settings/account_settings_screen.dart';
import 'package:private_cinema_ios/admin/screens/ott_providers/ott_providers_screen.dart';
import 'package:private_cinema_ios/admin/screens/link_checker/link_checker_screen.dart';
import 'package:private_cinema_ios/admin/widgets/navigation/app_drawer.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: _AdminApp(),
    );
  }
}

class _AdminApp extends ConsumerWidget {
  const _AdminApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_adminRouterProvider);
    return MaterialApp.router(
      title: 'Go. Admin',
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final _adminRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const AdminSplashWrapper(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(
          child: child,
          currentRoute: state.matchedLocation,
        ),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/movies', builder: (context, state) => const MoviesScreen()),
          GoRoute(path: '/iptv', builder: (context, state) => const IptvScreen()),
          GoRoute(path: '/add-movie', builder: (context, state) => const AddMovieScreen()),
          GoRoute(path: '/edit-movie', builder: (context, state) {
            final id = state.uri.queryParameters['id'] ?? '';
            return EditMovieScreen(movieId: id);
          }),
          GoRoute(path: '/languages', builder: (context, state) => const LanguagesScreen()),
          GoRoute(path: '/iptv-settings', builder: (context, state) => const IptvSettingsScreen()),
          GoRoute(path: '/app-settings', builder: (context, state) => const AppSettingsScreen()),
          GoRoute(path: '/bulk-updater', builder: (context, state) => const BulkUpdaterScreen()),
          GoRoute(path: '/streamtape', builder: (context, state) => const StreamtapeScreen()),
          GoRoute(path: '/backups', builder: (context, state) => const BackupsScreen()),
          GoRoute(path: '/account-settings', builder: (context, state) => const AccountSettingsScreen()),
          GoRoute(path: '/ott-providers', builder: (context, state) => const OttProvidersScreen()),
          GoRoute(path: '/link-checker', builder: (context, state) => const LinkCheckerScreen()),
        ],
      ),
    ],
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isLogin = location == '/login';
      if (isSplash) return null;
      if (!isLoggedIn && !isLogin) return '/login';
      if (isLoggedIn && isLogin) return '/dashboard';
      return null;
    },
  );
});

class MainShell extends ConsumerWidget {
  final Widget child;
  final String currentRoute;
  const MainShell({super.key, required this.child, required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: DrawerProvider.scaffoldKey,
      drawer: AppDrawer(currentRoute: currentRoute),
      body: child,
    );
  }
}

class AdminSplashWrapper extends StatelessWidget {
  const AdminSplashWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SplashScreen(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: 'Exit Admin Panel',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
    );
  }
}
