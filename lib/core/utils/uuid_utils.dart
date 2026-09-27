import 'dart:math';

/// Utility to generate RFC4122 v4 UUID strings client-side.
///
/// Uses [Random.secure] for cryptographically secure pseudo-random numbers.
class UuidUtils {
  UuidUtils._();

  static final Random _secureRandom = Random.secure();

  /// Generates a random v4 UUID string.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));

    // Set version to 0100 (v4)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to 10xx (RFC 4122)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Generates a deterministic v4-format UUID from a namespace and integer ID or key string.
  /// Useful for safe legacy migrations where old integer IDs must map deterministically.
  static String deterministic(String namespace, dynamic key) {
    // Generate a reproducible pseudo-random byte stream using the key hash.
    final combined = '$namespace:$key';
    int hash = 5381;
    for (int i = 0; i < combined.length; i++) {
      hash = ((hash << 5) + hash) ^ combined.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }

    final rng = Random(hash);
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
