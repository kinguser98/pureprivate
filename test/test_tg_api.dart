import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebuff_core/services/telegram/telegram_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tg/tg.dart' as tg;
import 'package:t/t.dart' as t;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Check exportAuthorization / importAuthorization classes compile', () async {
    // 1. Verify we can construct t.AuthExportAuthorization
    const exportReq = t.AuthExportAuthorization(dcId: 4);
    print('ExportReq: $exportReq');

    // 2. Verify we can construct t.AuthImportAuthorization
    final importReq = t.AuthImportAuthorization(
      id: 12345,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    print('ImportReq: $importReq');
  });

  test('Test localId parsing with negative numbers and multiple hyphens', () async {
    // Test case 1: Positive numbers
    final parts1 = TelegramStreamProxy.parseLocalIdParts('doc-12345-67890-4');
    expect(parts1, equals(['doc', '12345', '67890', '4']));

    // Test case 2: Negative accessHash (double hyphen)
    final parts2 = TelegramStreamProxy.parseLocalIdParts('doc-6150184655799721647--5088309725101633894-5');
    expect(parts2, equals(['doc', '6150184655799721647', '-5088309725101633894', '5']));

    // Test case 3: Negative documentId and accessHash
    final parts3 = TelegramStreamProxy.parseLocalIdParts('doc--12345--67890-4');
    expect(parts3, equals(['doc', '-12345', '-67890', '4']));

    print('✅ LocalId parser tests completed successfully!');
  });
}
