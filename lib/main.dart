import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connection_monitor.dart';
import 'router.dart';
import 'theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ConnectionMonitor.instance.start();
  runApp(const ProviderScope(child: SlkApp()));
}

class SlkApp extends ConsumerWidget {
  const SlkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final theme = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'SLK Mobile',
      debugShowCheckedModeBanner: false,
      theme: theme.toThemeData(),
      routerConfig: router,
      // On wide screens (tablets/foldables) keep the UI in a comfortable
      // phone-width column rather than stretching edge to edge.
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final Widget page = width <= 720 || child == null
            ? (child ?? const SizedBox.shrink())
            : ColoredBox(
                color: const Color(0xFFE7DDD0),
                child: Center(
                  child: SizedBox(width: 600, child: child),
                ),
              );
        // The connection light, over every screen: top-right, just below
        // the status bar. Green — the server answers; red — it does not.
        return Stack(
          children: [
            page,
            Positioned(
              top: MediaQuery.paddingOf(context).top + 5,
              right: 7,
              child: const IgnorePointer(child: ConnectionLight()),
            ),
          ],
        );
      },
    );
  }
}
