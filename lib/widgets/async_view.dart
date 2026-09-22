import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'skeleton.dart';
import 'ui/states.dart';

/// Renders an [AsyncValue] with consistent loading / error / empty states so
/// every screen behaves the same. [onRetry] re-runs the underlying provider.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.isEmpty,
    this.emptyMessage = 'Nothing here yet.',
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const SkeletonList(),
      error: (err, _) => ErrorState(message: '$err', onRetry: onRetry),
      data: (d) {
        if (isEmpty != null && isEmpty!(d)) {
          return EmptyState(title: emptyMessage);
        }
        return data(d);
      },
    );
  }
}

/// Small helper to surface an [ApiException] (or anything) as a SnackBar.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('$error'), backgroundColor: context.p.danger),
    );
}

void showOk(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.p.success),
    );
}
