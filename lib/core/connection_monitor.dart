import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';

enum ConnectionState2 { unknown, online, offline }

/// Whether the app can reach slk-core right now — what the small green or
/// red light in the corner of every screen shows.
///
/// Two sources, so the light is both prompt and honest: every real request
/// the app makes reports whether the server answered (see ApiClient), and a
/// tiny "are you there" check (`/api/v1/ping`) runs every 15 seconds in
/// between, so a lost connection shows even on a screen that is only being
/// looked at. Any answer from the server counts as online — even a refusal
/// is proof the connection works; only no answer at all is offline.
class ConnectionMonitor extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionMonitor._();
  static final ConnectionMonitor instance = ConnectionMonitor._();

  static const _every = Duration(seconds: 15);

  ConnectionState2 _state = ConnectionState2.unknown;
  ConnectionState2 get state => _state;

  Timer? _timer;
  bool _started = false;
  bool _probing = false;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      validateStatus: (_) => true,
    ),
  );

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    probe();
    _timer = Timer.periodic(_every, (_) => probe());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      probe();
      _timer ??= Timer.periodic(_every, (_) => probe());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> probe() async {
    if (_probing) return;
    _probing = true;
    try {
      await _dio.get<dynamic>('${CoreConfig.apiRoot}/ping');
      report(true);
    } on DioException catch (e) {
      report(e.response != null);
    } catch (_) {
      report(false);
    } finally {
      _probing = false;
    }
  }

  /// Called with the outcome of any request to slk-core.
  void report(bool reached) {
    final next = reached ? ConnectionState2.online : ConnectionState2.offline;
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}

/// The light itself: a small dot laid over the top-right corner of every
/// screen. Green: the server answers. Red: it cannot be reached — scans are
/// kept on the phone until it can. Grey for the first moment, before the
/// first check has come back.
class ConnectionLight extends StatelessWidget {
  const ConnectionLight({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectionMonitor.instance,
      builder: (context, _) {
        final state = ConnectionMonitor.instance.state;
        final color = switch (state) {
          ConnectionState2.online => const Color(0xFF34C759),
          ConnectionState2.offline => const Color(0xFFFF3B30),
          ConnectionState2.unknown => const Color(0xFF9E9E9E),
        };
        final label = switch (state) {
          ConnectionState2.online => 'Connected to the server',
          ConnectionState2.offline => 'No connection to the server',
          ConnectionState2.unknown => 'Checking the connection',
        };
        return Semantics(
          label: label,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFFFFF), width: 1.5),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
        );
      },
    );
  }
}
