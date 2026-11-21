/// Error categories the UI knows how to describe to the user.
enum AppErrorKind {
  wrongCredential,
  lockedOut,
  corruptedData,
  storageFull,
  permissionDenied,
  fileNotFound,
  invalidBackup,
  cancelled,
  unknown,
}

/// Single exception type thrown across layer boundaries.
///
/// Lower layers convert platform / IO / crypto exceptions into an
/// [AppException] so presentation code only has to handle one type.
class AppException implements Exception {
  const AppException(this.kind, [this.debugMessage, this.cause]);

  final AppErrorKind kind;

  /// Developer-facing detail. Never shown to users and never contains
  /// user data.
  final String? debugMessage;
  final Object? cause;

  @override
  String toString() =>
      'AppException($kind${debugMessage == null ? '' : ': $debugMessage'})';
}
