import 'package:flutter_test/flutter_test.dart';
import 'package:private_cinema_mobile/data/moviebox_resolver.dart';

void main() {
  test('Test Moviebox Strict Year Resolution', () async {
    print('Starting MovieboxResolver year test...');
    try {
      print('=== KGF (2018) ===');
      final streams1 = await MovieboxResolver.resolveStreams(title: 'KGF', year: '2018');
      print('Found ${streams1.length} streams');
      for (final s in streams1) {
        print(' - Name: ${s.name}');
      }

      print('\n=== Avatar (2009) ===');
      final streams2 = await MovieboxResolver.resolveStreams(title: 'Avatar', year: '2009');
      print('Found ${streams2.length} streams');
      for (final s in streams2) {
        print(' - Name: ${s.name}');
      }
    } catch (e, st) {
      print('❌ FAILED: $e\n$st');
    }
  });
}
