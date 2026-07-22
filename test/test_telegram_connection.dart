import 'package:flutter_test/flutter_test.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Test Telegram Connection and Initialization', () async {
    SharedPreferences.setMockInitialValues({});
    
    print('Starting Telegram connection test...');
    final service = TelegramService.instance;
    
    // Explicitly set credentials to match the user's setup
    await service.setCredentials(33277125, '7e37090b48b6e4a2dfe159be13c1e916');
    
    try {
      print('Calling init()...');
      await service.init();
      print('Status: ${service.status.value}');
      print('Status Message: ${service.statusMessage.value}');
      
      if (service.status.value == TelegramStatus.error) {
        print('❌ INIT FAILED: ${service.statusMessage.value}');
      } else {
        print('✅ INIT SUCCESSFUL!');
        
        print('Testing startAuth with sample number...');
        try {
          await service.startAuth('+919999999999');
          print('Status after startAuth: ${service.status.value}');
        } catch (authError) {
          print('startAuth completed/failed (expected behavior): $authError');
        }
      }
    } catch (e) {
      print('❌ EXCEPTION CAUGHT during init: $e');
    }
  });
}
