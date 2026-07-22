import 'package:flutter_test/flutter_test.dart';
import 'package:private_cinema_mobile/data/stalker_resolver.dart';

void main() {
  test('Test Stalker Stream Resolution on Portal 3', () async {
    print('Starting Stalker resolution test...');
    try {
      final stalkerStream = await StalkerResolver.resolveStream('/media/467381.mpg', 3, isLive: false);
      print('✅ SUCCESS!');
      print('Resolved URL: ${stalkerStream.url}');
      print('Resolved Headers: ${stalkerStream.headers}');
    } catch (e) {
      print('❌ FAILED: $e');
    }
  });
}
