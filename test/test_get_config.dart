import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tg/tg.dart' as tg;
import 'package:t/t.dart' as t;

class TestSocket extends tg.SocketAbstraction {
  final Socket socket;
  @override
  final Stream<Uint8List> receiver;
  TestSocket(this.socket) : receiver = socket.asBroadcastStream();

  @override
  Future<void> send(List<int> data) async {
    socket.add(data);
    await socket.flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fetch Live Telegram DC Options', () async {
    SharedPreferences.setMockInitialValues({});
    final service = TelegramService.instance;
    await service.setCredentials(33277125, '7e37090b48b6e4a2dfe159be13c1e916');
    
    try {
      print('Calling init()...');
      await service.init();
      
      print('Status: ${service.status.value}');
      
      final creds = await service.getCredentials();
      
      print('Connecting directly to DC 2 via Socket.connect on port 80...');
      final socket = await Socket.connect('149.154.167.50', 80, timeout: const Duration(seconds: 10));
      
      final testSocket = TestSocket(socket);
      final obfuscation = tg.Obfuscation.random(false, 2);
      final idGenerator = tg.MessageIdGenerator();
      socket.add(obfuscation.preamble);
      await socket.flush();
      
      print('Performing handshake...');
      final authKey = await tg.Client.authorize(testSocket, obfuscation, idGenerator);
      final client = tg.Client(
        socket: testSocket,
        obfuscation: obfuscation,
        authorizationKey: authKey,
        idGenerator: idGenerator,
      );
      
      print('Initializing MTProto Connection...');
      final cfgRes = await client.initConnection<t.Config>(
        apiId: creds!.apiId,
        deviceModel: 'GoXio Test',
        systemVersion: '1.0',
        appVersion: '1.0.0',
        systemLangCode: 'en',
        langPack: '',
        langCode: 'en',
        query: const t.HelpGetConfig(),
      );
      
      if (cfgRes.error != null) {
        print('❌ HelpGetConfig Error: ${cfgRes.error!.errorMessage}');
        return;
      }
      
      final cfg = cfgRes.result as t.Config;
      print('✅ HelpGetConfig Success!');
      print('Found ${cfg.dcOptions.length} DC options:');
      
      for (final optionBase in cfg.dcOptions) {
        if (optionBase is t.DcOption) {
          print('DC ${optionBase.id}: ${optionBase.ipAddress}:${optionBase.port} (ipv6: ${optionBase.ipv6}, mediaOnly: ${optionBase.mediaOnly})');
        } else {
          print('Unknown DC option type: ${optionBase.runtimeType}');
        }
      }
      
      socket.destroy();
    } catch (e) {
      print('❌ ERROR: $e');
    }
  });
}
