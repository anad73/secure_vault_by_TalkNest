import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../logging/app_logger.dart';
import 'app_exception.dart';

/// Converts any thrown object into an [AppException].
AppException toAppException(Object error, [StackTrace? stack]) {
  if (error is AppException) return error;
  if (error is SecretBoxAuthenticationError) {
    return AppException(AppErrorKind.corruptedData, 'GCM tag mismatch', error);
  }
  if (error is PathNotFoundException) {
    return AppException(AppErrorKind.fileNotFound, error.message, error);
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // ENOSPC = 28 on Linux/Android.
    if (code == 28) {
      return AppException(AppErrorKind.storageFull, error.message, error);
    }
    return AppException(AppErrorKind.unknown, error.message, error);
  }
  if (error is PlatformException) {
    return AppException(AppErrorKind.unknown, error.code, error);
  }
  AppLogger.error('Error', 'Unmapped error', error, stack);
  return AppException(
      AppErrorKind.unknown, error.runtimeType.toString(), error);
}

/// User-facing, localised message for an error.
String describeError(AppStrings s, Object error) {
  final e = toAppException(error);
  return switch (e.kind) {
    AppErrorKind.wrongCredential => s.errWrongCredential,
    AppErrorKind.lockedOut => s.errLockedOut,
    AppErrorKind.corruptedData => s.errCorrupted,
    AppErrorKind.storageFull => s.errStorageFull,
    AppErrorKind.permissionDenied => s.errPermission,
    AppErrorKind.fileNotFound => s.errFileNotFound,
    AppErrorKind.invalidBackup => s.errInvalidBackup,
    AppErrorKind.cancelled => s.errCancelled,
    AppErrorKind.unknown => s.errUnknown,
  };
}
