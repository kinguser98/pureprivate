import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'utils/drawer_helper.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/movies/movies_screen.dart';
import 'screens/iptv/iptv_screen.dart';
import 'screens/add_movie/add_movie_screen.dart';
import 'screens/edit_movie/edit_movie_screen.dart';
import 'screens/languages/languages_screen.dart';
import 'screens/master_channels/master_channels_screen.dart';
import 'screens/iptv_settings/iptv_settings_screen.dart';
import 'screens/app_settings/app_settings_screen.dart';
import 'screens/bulk_updater/bulk_updater_screen.dart';
import 'screens/streamtape/streamtape_screen.dart';
import 'screens/backups/backups_screen.dart';
import 'screens/account_settings/account_settings_screen.dart';
import 'screens/ott_providers/ott_providers_screen.dart';
import 'screens/link_checker/link_checker_screen.dart';
import 'screens/1tamilmv_converter/1tamilmv_converter_screen.dart';
import 'widgets/navigation/app_drawer.dart';

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
          GoRoute(path: '/master-channels', builder: (context, state) => const MasterChannelsScreen()),
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
          GoRoute(path: '/1tamilmv-converter', builder: (context, state) => const OneTamilmvConverterScreen()),
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
