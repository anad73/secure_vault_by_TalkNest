import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/design/app_theme.dart';
import 'core/design/tokens.dart';
import 'core/logging/app_logger.dart';
import 'core/widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Centralised handling of uncaught errors (never logs user data).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter', details.exceptionAsString(), details.exception,
        details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught', 'Unhandled async error', error, stack);
    return true;
  };

  runApp(const _Bootstrap());
}

/// Initialises storage, database and services, showing a branded splash
/// meanwhile and a retry screen if startup fails.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppDependencies> _deps = AppDependencies.create();

  void _retry() => setState(() => _deps = AppDependencies.create());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _deps,
      builder: (context, snap) {
        if (snap.hasData) return SafeVaultApp(deps: snap.data!);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GradientBadge(icon: Icons.shield_rounded),
                  const SizedBox(height: Space.xl),
                  if (snap.hasError) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Space.xxl),
                      child: Text(
                        'Safe Vault could not start. Your files are untouched.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ] else
                    const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
