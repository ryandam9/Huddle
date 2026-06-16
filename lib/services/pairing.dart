import 'dart:math';

/// Number of digits in a pairing code shown during the handshake.
const int kPairingCodeLength = 6;

final Random _rng = Random.secure();

/// Generates a fresh, zero-padded numeric pairing code (e.g. `"048213"`).
///
/// The initiator displays this code; the other device's user must type it in
/// to complete the agreement, proving the two humans are physically together
/// rather than a silent peer on the network impersonating someone.
String generatePairingCode() {
  final max = pow(10, kPairingCodeLength).toInt(); // 1_000_000 for length 6
  return _rng.nextInt(max).toString().padLeft(kPairingCodeLength, '0');
}

/// Constant-ish comparison of a typed code against the expected one, ignoring
/// surrounding whitespace.
bool pairingCodeMatches(String? expected, String? entered) {
  if (expected == null || entered == null) return false;
  return expected.trim() == entered.trim() && expected.trim().isNotEmpty;
}
