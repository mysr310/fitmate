import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers.dart';
import 'ui/onboarding/onboarding_page.dart';
import 'ui/root_shell.dart';
import 'ui/settings/restore_flow.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class FitMateApp extends ConsumerStatefulWidget {
  const FitMateApp({super.key});

  @override
  ConsumerState<FitMateApp> createState() => _FitMateAppState();
}

class _FitMateAppState extends ConsumerState<FitMateApp> {
  AppLifecycleListener? _lifecycle;
  MethodChannel? _intentChannel;
  bool _handlingIntent = false;

  @override
  void initState() {
    super.initState();
    // R3-高4：回到前台时把"今天"对齐到新的一天，并触发每日自动备份
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(selectedDateProvider.notifier).refreshIfWasToday();
        // R4-N3：Today/训练/体重页不依赖 selectedDateProvider，跨午夜
        // 恢复时显式触发一次重建
        ref.read(uiRefreshProvider.notifier).bump();
        ref.read(backupServiceProvider).maybeAutoBackup();
      },
    );
    // 首次启动：清理崩溃残留的暂存目录 + 每日自动备份检查
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final svc = ref.read(backupServiceProvider);
      svc.cleanupStaging();
      svc.maybeAutoBackup();
    });
    _setupBackupIntentChannel();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _intentChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  /// R3-高3：接收 Android「用其他应用打开 .fitbak」的缓存文件路径，
  /// 直接进入恢复确认流程（微信点开文件 → 健身管家即可恢复）
  void _setupBackupIntentChannel() {
    _intentChannel = const MethodChannel('fitmate/backup_intent');
    _intentChannel!.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBackupFile':
          _consumeBackupIntent(call.arguments as String?);
          break;
        case 'getInitialBackupPath':
          // 冷启动时原生层缓存了 intent；这里通知原生"已就绪"，由原生推送
          break;
      }
      return null;
    });
    // Dart 就绪后主动拉取冷启动缓存的 intent
    _intentChannel!
        .invokeMethod<String>('getInitialBackupPath')
        .then((path) {
      if (path != null && path.isNotEmpty) {
        _consumeBackupIntent(path);
      }
    }, onError: (_) {});
  }

  void _consumeBackupIntent(String? path) {
    if (path == null || path.isEmpty || _handlingIntent || !mounted) return;
    _handlingIntent = true;
    final ctx = _rootNavigatorKey.currentContext;
    if (ctx == null) {
      _handlingIntent = false;
      return;
    }
    runBackupRestoreFlow(ctx, ref, path).whenComplete(() => _handlingIntent = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '健身管家',
      debugShowCheckedModeBanner: false,
      navigatorKey: _rootNavigatorKey,
      theme: lightTheme(),
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
