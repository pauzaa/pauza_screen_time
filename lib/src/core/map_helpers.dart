/// Safe numeric-to-int cast for platform channel payloads.
///
/// The Flutter platform channel may deliver 64-bit integers as [int] on
/// Android but as [num] in some edge cases.
int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw ArgumentError.value(value, 'value', 'Expected a numeric type, got ${value.runtimeType}');
}
