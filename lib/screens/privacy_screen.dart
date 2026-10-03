import 'package:flutter/material.dart';

/// Health Connect links to an app's privacy policy from its permission screen.
/// For this internal proof of concept, the policy is shown in-app.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Health Demo is an internal proof of concept.\n\n'
            'What it reads: steps, active energy, heart rate, resting heart rate, '
            'sleep, and workouts from Apple Health (iPhone) or Health Connect (Android), '
            'only after you grant permission.\n\n'
            'What it writes: only the test heart rate and step samples you create with '
            'the "Test the connection" buttons.\n\n'
            'Where your data goes: nowhere. Everything is read and displayed on this '
            'phone only. Nothing is uploaded, stored on a server, or shared.\n\n'
            'You can revoke access at any time in the Health app (iPhone) or the '
            'Health Connect settings (Android).',
            style: body,
          ),
        ],
      ),
    );
  }
}
