import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppDrawer extends ConsumerWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    return Drawer(
      backgroundColor: const Color(0xFF0B0F19),
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(child: Text('G', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(height: 12),
                  Text(authState.username ?? 'Admin', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Management Hub', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, letterSpacing: 1)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _navItem(context, ref, Icons.dashboard, 'Analytics', '/dashboard', currentRoute == '/dashboard'),
                  _divider(),
                  _sectionHeader('Content'),
                  _navItem(context, ref, Icons.add_circle_outline, 'Add Movie', '/add-movie', false),
                  _navItem(context, ref, Icons.movie, 'All Movies', '/movies', currentRoute == '/movies'),
                  _navItem(context, ref, Icons.language, 'Languages', '/languages', false),
                  _divider(),
                  _sectionHeader('IPTV'),
                  _navItem(context, ref, Icons.tv, 'IPTV Channels', '/iptv', currentRoute == '/iptv'),
                  _navItem(context, ref, Icons.settings_input_component, 'IPTV Settings', '/iptv-settings', false),
                  _divider(),
                  _sectionHeader('Tools'),
                  _navItem(context, ref, Icons.find_replace, 'Bulk Updater', '/bulk-updater', false),
                  _navItem(context, ref, Icons.link, 'Link Checker', '/link-checker', false),
                  _navItem(context, ref, Icons.storage, 'Streamtape', '/streamtape', false),
                  _divider(),
                  _sectionHeader('System'),
                  _navItem(context, ref, Icons.settings, 'App Settings', '/app-settings', false),
                  _navItem(context, ref, Icons.backup, 'Backups', '/backups', false),
                  _navItem(context, ref, Icons.people, 'OTT Providers', '/ott-providers', false),
                  _navItem(context, ref, Icons.person, 'Account', '/account-settings', false),
                  _divider(),
                  _navItem(context, ref, Icons.logout, 'Logout', '/logout', false, color: Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(color: Colors.white.withOpacity(0.06), height: 1),
    );
  }

  Widget _navItem(BuildContext context, WidgetRef ref, IconData icon, String label, String route, bool isActive, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: color ?? (isActive ? Colors.white : Colors.white.withOpacity(0.5))),
          title: Text(label,
              style: TextStyle(
                  color: color ?? (isActive ? Colors.white : Colors.white.withOpacity(0.6)),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: isActive ? const Color(0xFFEF4444).withOpacity(0.15) : Colors.transparent,
          onTap: () {
            Navigator.pop(context);
            if (route == '/logout') {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            } else {
              context.go(route);
            }
          },
        ),
      ),
    );
  }
}
