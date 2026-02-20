import 'package:flutter/services.dart';

/// Base typed plugin error used by host apps.
sealed class PauzaError implements Exception {
  const PauzaError({required this.message, this.details, this.rawCode});

  /// Human-readable error message.
  final String message;

  /// Structured diagnostic payload from native layers.
  final Object? details;

  /// Original platform code (usually taxonomy code).
  final String? rawCode;

  /// Stable taxonomy code.
  String get code;

  /// Converts [PlatformException] into a typed [PauzaError].
  factory PauzaError.fromPlatformException(PlatformException exception) {
    final message = exception.message ?? 'A platform error occurred (${exception.code})';
    switch (exception.code) {
      case 'UNSUPPORTED':
        return PauzaUnsupportedError(message: message, details: exception.details, rawCode: exception.code);
      case 'MISSING_PERMISSION':
        return PauzaMissingPermissionError(message: message, details: exception.details, rawCode: exception.code);
      case 'PERMISSION_DENIED':
        return PauzaPermissionDeniedError(message: message, details: exception.details, rawCode: exception.code);
      case 'SYSTEM_RESTRICTED':
        return PauzaSystemRestrictedError(message: message, details: exception.details, rawCode: exception.code);
      case 'INVALID_ARGUMENT':
        return PauzaInvalidArgumentError(message: message, details: exception.details, rawCode: exception.code);
      default:
        return PauzaInternalFailureError(message: message, details: exception.details, rawCode: exception.code);
    }
  }

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

final class PauzaUnsupportedError extends PauzaError {
  const PauzaUnsupportedError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'UNSUPPORTED';
}

final class PauzaMissingPermissionError extends PauzaError {
  const PauzaMissingPermissionError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'MISSING_PERMISSION';
}

final class PauzaPermissionDeniedError extends PauzaError {
  const PauzaPermissionDeniedError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'PERMISSION_DENIED';
}

final class PauzaSystemRestrictedError extends PauzaError {
  const PauzaSystemRestrictedError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'SYSTEM_RESTRICTED';
}

final class PauzaInvalidArgumentError extends PauzaError {
  const PauzaInvalidArgumentError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'INVALID_ARGUMENT';
}

final class PauzaInternalFailureError extends PauzaError {
  const PauzaInternalFailureError({required super.message, super.details, super.rawCode});

  @override
  String get code => 'INTERNAL_FAILURE';
}

extension PauzaFutureErrorX<T> on Future<T> {
  /// Re-throws platform errors as typed [PauzaError].
  Future<T> throwTypedPauzaError() async {
    try {
      return await this;
    } on PauzaError {
      rethrow;
    } on PlatformException catch (exception) {
      throw PauzaError.fromPlatformException(exception);
    } on UnsupportedError catch (error) {
      throw PauzaUnsupportedError(message: error.message ?? 'Operation is not supported');
    } catch (error) {
      throw PauzaInternalFailureError(message: error.toString());
    }
  }
}
