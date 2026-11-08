import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

// Compatibility route for a previous version's unfinished onboarding.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.pluginsController,
    required this.myController,
  });
  final PluginsController pluginsController;
  final MyController myController;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.navigate('/tab/catalog/'),
        child: const Text('开始观看'),
      ),
    ),
  );
}
