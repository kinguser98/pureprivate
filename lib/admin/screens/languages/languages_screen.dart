import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/drawer_helper.dart';

class LanguagesScreen extends ConsumerStatefulWidget {
  const LanguagesScreen({super.key});
  @override
  ConsumerState<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends ConsumerState<LanguagesScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: DrawerProvider.openDrawer),
        title: const Text('Languages'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.language, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text('Language Management', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18)),
            const SizedBox(height: 8),
            Text('Manage languages via the web admin panel', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F2E).withOpacity(0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  _languageItem('Malayalam', '1'),
                  _divider(),
                  _languageItem('Tamil', '2'),
                  _divider(),
                  _languageItem('Hindi', '3'),
                  _divider(),
                  _languageItem('English', '4'),
                  _divider(),
                  _languageItem('Telugu', '5'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(color: Colors.white.withOpacity(0.08), height: 1, indent: 16, endIndent: 16);

  Widget _languageItem(String name, String id) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: const Color(0xFF3B82F6), shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('ID: $id', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
        ],
      ),
    );
  }
}
