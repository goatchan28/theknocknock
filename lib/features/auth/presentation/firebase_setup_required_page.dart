import 'package:flutter/material.dart';

class FirebaseSetupRequiredPage extends StatelessWidget {
  const FirebaseSetupRequiredPage({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Firebase setup required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Phase 1 expects Firebase to be configured for this app. '
                'Run FlutterFire setup and platform config, then restart.',
              ),
              const SizedBox(height: 16),
              Text(
                'Initialization error:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(error?.toString() ?? 'Unknown initialization error'),
            ],
          ),
        ),
      ),
    );
  }
}
