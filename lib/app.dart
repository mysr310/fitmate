import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers.dart';
import 'ui/onboarding/onboarding_page.dart';
import 'ui/root_shell.dart';

class FitMateApp extends ConsumerWidget {
  const FitMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '健身管家',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const _EntryGate(),
    );
  }
}

ThemeData appTheme() => lightTheme();

class _EntryGate extends ConsumerWidget {
  const _EntryGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('数据加载失败：$e', textAlign: TextAlign.center)),
      ),
      data: (profile) => profile == null ? const OnboardingPage() : const RootShell(),
    );
  }
}
