import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'core_auth.dart';
import 'core_photos.dart';

/// Photographing a record that exists.
///
/// Separate from the entry form because the two are separate acts, minutes or
/// days apart and often different people: choosing which photographs a product
/// needs is a decision, and taking them is work. A slot with no file is the
/// shot list, which is the useful half of this screen until somebody gets to
/// it with the saree in their hands.
///
/// It needs a record to exist — a photograph belongs to a colourway and there
/// is nowhere to put one before there is a colourway — so this is reached
/// after creating, never before.
class RecordPhotosScreen extends ConsumerStatefulWidget {
  const RecordPhotosScreen({
    super.key,
    required this.recordId,
    required this.code,
  });

  final String recordId;

  /// The design code, shown so somebody photographing a pile of sarees can see
  /// which one this screen is about.
  final String code;

  @override
  ConsumerState<RecordPhotosScreen> createState() => _RecordPhotosScreenState();
}

class _RecordPhotosScreenState extends ConsumerState<RecordPhotosScreen> {
  /// Slot id → the local file being sent, while it is being sent.
  final Map<String, File> _sending = {};

  late Future<_Slots> _slots = _load();

  Future<_Slots> _load() async {
    final api = ref.read(coreApiProvider);

    final record = await api.get('/records/${widget.recordId}');
    final data = (record as Map).cast<String, dynamic>();

    final images = [
      for (final row in (data['images'] as List? ?? const []))
        (row as Map).cast<String, dynamic>(),
    ];

    final options = await ref.read(coreOptionsProvider.future);

    return _Slots(
      // Only the slots this record actually wants. The vocabulary holds every
      // slot there is; this record asked for some of them.
      wanted: [
        for (final image in images)
          if (image['slotId'] != null)
            _Slot(
              id: image['slotId'] as String,
              label: _labelOf(options, image['slotId'] as String),
              url: image['url'] as String?,
            ),
      ],
    );
  }

  String _labelOf(CoreOptions options, String id) {
    for (final o in options['image_slot'] ?? const <CoreOption>[]) {
      if (o.id == id) return o.label;
    }
    return 'Photograph';
  }

  void _refresh() => setState(() => _slots = _load());

  Future<void> _pick(_Slot slot, ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // The same limits the rest of the app uses. A 12MP original is refused
      // by the API at 12MB anyway, and nothing downstream wants the pixels.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );

    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() => _sending[slot.id] = file);

    try {
      await ref.read(corePhotosProvider).upload(
            recordId: widget.recordId,
            slotId: slot.id,
            file: file,
          );

      if (!mounted) return;
      showOk(context, '${slot.label} saved.');
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending.remove(slot.id));
    }
  }

  Future<void> _remove(_Slot slot) async {
    try {
      await ref
          .read(corePhotosProvider)
          .remove(recordId: widget.recordId, slotId: slot.id);

      if (!mounted) return;
      showOk(context, '${slot.label} removed. The slot is still wanted.');
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _choose(_Slot slot) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.p.surface2,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Photograph the ${slot.label.toLowerCase()}'),
              onTap: () {
                Navigator.pop(sheet);
                _pick(slot, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from the gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _pick(slot, ImageSource.gallery);
              },
            ),
            if (slot.url != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: context.p.danger),
                title: Text(
                  'Remove this photograph',
                  style: TextStyle(color: context.p.danger),
                ),
                subtitle: const Text('The slot stays on the shot list'),
                onTap: () {
                  Navigator.pop(sheet);
                  _remove(slot);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(coreStorageProvider);

    return Scaffold(
      backgroundColor: context.p.surface1,
      appBar: AppBar(title: Text('Photographs · ${widget.code}')),
      body: AsyncView<StorageState>(
        value: storage,
        onRetry: () => ref.invalidate(coreStorageProvider),
        data: (state) => FutureBuilder<_Slots>(
          future: _slots,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Retry(message: '${snap.error}', onRetry: _refresh);
            }

            return _list(snap.data!, state);
          },
        ),
      ),
    );
  }

  Widget _list(_Slots slots, StorageState storage) {
    final p = context.p;

    if (slots.wanted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'This record asks for no photographs. Tick the slots it needs on '
            'the Images tab when creating it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Said before anyone takes a photograph, not after six of them fail.
        if (!storage.ready)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.danger.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photographs cannot be saved yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: p.danger,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Image storage is not set up on the server. Missing '
                  '${storage.missing.join(", ")}.',
                  style: TextStyle(fontSize: 12, color: p.danger, height: 1.4),
                ),
              ],
            ),
          ),

        for (final slot in slots.wanted)
          _SlotTile(
            slot: slot,
            sending: _sending.containsKey(slot.id),
            enabled: storage.ready,
            onTap: () => _choose(slot),
          ),
      ],
    );
  }
}

class _Slots {
  const _Slots({required this.wanted});
  final List<_Slot> wanted;
}

class _Slot {
  const _Slot({required this.id, required this.label, this.url});

  final String id;
  final String label;

  /// Null until a photograph exists — which is what makes this a shot list.
  final String? url;
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.sending,
    required this.enabled,
    required this.onTap,
  });

  final _Slot slot;
  final bool sending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final taken = slot.url != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: sending
                ? Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.primary,
                      ),
                    ),
                  )
                : taken
                    ? Image.network(
                        slot.url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: p.surface3,
                          child: Icon(Icons.broken_image_outlined,
                              color: p.textMuted),
                        ),
                      )
                    : Container(
                        color: p.surface3,
                        child: Icon(Icons.photo_camera_outlined,
                            color: p.textMuted),
                      ),
          ),
        ),
        title: Text(
          slot.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          sending
              ? 'Sending…'
              : taken
                  ? 'Photographed'
                  : 'Still to be taken',
          style: TextStyle(
            fontSize: 12,
            color: taken ? p.success : p.textSecondary,
          ),
        ),
        trailing: Icon(
          taken ? Icons.more_horiz : Icons.add_a_photo_outlined,
          color: enabled ? p.text : p.textMuted,
        ),
        onTap: sending || !enabled ? null : onTap,
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.p.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
