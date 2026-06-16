// Tests for the pairing-code helpers.

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/pairing.dart';

void main() {
  group('generatePairingCode', () {
    test('is always the configured length and numeric (zero padded)', () {
      for (var i = 0; i < 500; i++) {
        final code = generatePairingCode();
        expect(code.length, kPairingCodeLength);
        expect(int.tryParse(code), isNotNull);
      }
    });

    test('produces varying codes', () {
      final codes = {for (var i = 0; i < 50; i++) generatePairingCode()};
      // Astronomically unlikely for 50 six-digit draws to collapse to one.
      expect(codes.length, greaterThan(1));
    });
  });

  group('pairingCodeMatches', () {
    test('matches identical codes, ignoring surrounding whitespace', () {
      expect(pairingCodeMatches('048213', '048213'), isTrue);
      expect(pairingCodeMatches('048213', '  048213 '), isTrue);
    });

    test('rejects mismatches, nulls and blanks', () {
      expect(pairingCodeMatches('048213', '048214'), isFalse);
      expect(pairingCodeMatches('048213', null), isFalse);
      expect(pairingCodeMatches(null, '048213'), isFalse);
      expect(pairingCodeMatches('', ''), isFalse);
    });
  });
}
