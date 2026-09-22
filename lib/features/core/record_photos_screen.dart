import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'core_auth.dart';
import 'core_photos.dart';
import 'guided_capture_screen.dart';

/// What to tell the person when a photograph did not arrive.
///
/// The API writes its refusals for whoever is holding the phone, so those
/// are shown as they are. A dropped connection to storage is a Dio error
/// whose toString is a wall of request internals nobody on a floor can act
/// on — that one gets a plain line, and the original goes to the log.
String _uploadFailureMessage(Object e) =>
    e is ApiException ? e.message : 'Upload failed. Check the connection and try again.';

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

  /// The product code, shown so somebody photographing a stack of sarees can
  /// see which one this screen is about.
  ///
  /// The consignment — 300042 — because that is what is written on what they
  /// are holding. Callers fall back to the design code only for a record
  /// nothing has arrived against yet, where there is no product code to show.
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
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        // The same limits the rest of the app uses. A 12MP original is
        // refused by the API at 12MB anyway, and nothing downstream wants
        // the pixels.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      // The camera denied, a permission dialog dismissed — image_picker
      // throws rather than returning null, and with nothing catching it
      // that used to close the sheet with no visible reason why.
      if (mounted) showError(context, e);
      return;
    }

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
    } catch (e, stack) {
      debugPrint('Upload of ${slot.id} failed: $e\n$stack');
      if (mounted) showError(context, _uploadFailureMessage(e));
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

  /// The guided camera, starting on [first] and carrying on through every
  /// other slot still waiting — a saree is four photographs, and the point
  /// of the guide is that they are taken in one go without coming back to
  /// this list between each. Each accepted capture is sent straight away;
  /// a failed send is thrown back to the camera, which offers the slot
  /// again rather than moving on past a photograph that never arrived.
  Future<void> _guided(_Slot first, List<_Slot> all) async {
    final queue = [
      first,
      for (final s in all)
        if (s.id != first.id && s.url == null) s,
    ];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => GuidedCaptureScreen(
          slots: [for (final s in queue) CaptureSlot(id: s.id, label: s.label)],
          onCaptured: (slot, file) => ref.read(corePhotosProvider).upload(
                recordId: widget.recordId,
                slotId: slot.id,
                file: file,
              ),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  void _choose(_Slot slot, List<_Slot> all) {
    final p = context.p;
    showAppSheet<void>(
      context,
      title: slot.label,
      child: Builder(
        builder: (sheet) => AppListGroup(
          children: [
            AppListRow(
              leading: Icon(Icons.center_focus_strong_outlined, color: p.textSecondary),
              title: 'Photograph the ${slot.label.toLowerCase()}',
              subtitle: 'The frame tells you what to fix and takes the shot itself',
              onTap: () {
                Navigator.pop(sheet);
                _guided(slot, all);
              },
            ),
            AppListRow(
              leading: Icon(Icons.photo_library_outlined, color: p.textSecondary),
              title: 'Choose from the gallery',
              onTap: () {
                Navigator.pop(sheet);
                _pick(slot, ImageSource.gallery);
              },
            ),
            AppListRow(
              leading: Icon(Icons.photo_camera_outlined, color: p.textSecondary),
              title: 'Use the plain camera',
              subtitle: 'No guide, no checks',
              onTap: () {
                Navigator.pop(sheet);
                _pick(slot, ImageSource.camera);
              },
            ),
            if (slot.url != null)
              AppListRow(
                leading: Icon(Icons.delete_outline, color: p.danger),
                title: 'Remove this photograph',
                subtitle: 'The slot stays on the shot list',
                onTap: () async {
                  Navigator.pop(sheet);
                  // Irreversible from here — the file is gone from storage,
                  // and a photograph took somebody a trip to the shelf.
                  final sure = await showConfirmDialog(
                    context,
                    title: 'Remove the ${slot.label.toLowerCase()} photograph?',
                    message: 'The slot stays on the shot list, but the photograph '
                        'itself cannot be brought back.',
                    confirmLabel: 'Remove',
                    cancelLabel: 'Keep it',
                    danger: true,
                  );
                  if (sure && mounted) await _remove(slot);
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

    return AppPage(
      title: 'Photographs',
      subtitle: widget.code,
      padded: false,
      body: AsyncView<StorageState>(
        value: storage,
        onRetry: () => ref.invalidate(coreStorageProvider),
        data: (state) => FutureBuilder<_Slots>(
          future: _slots,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingState(rows: 4);
            }
            if (snap.hasError) {
              return ErrorState(message: '${snap.error}', onRetry: _refresh);
            }

            return _list(snap.data!, state);
          },
        ),
      ),
    );
  }

  Widget _list(_Slots slots, StorageState storage) {
    if (slots.wanted.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_camera_outlined,
        title: 'This record asks for no photographs.',
        message: 'Tick the slots it needs on the Images tab when creating it.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Said before anyone takes a photograph, not after six of them fail.
        if (!storage.ready)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InlineNotice(
              'Photographs cannot be saved yet. Image storage is not set up '
              'on the server. Missing ${storage.missing.join(", ")}.',
              icon: Icons.cloud_off_outlined,
              warning: true,
            ),
          ),

        AppListGroup(
          children: [
            for (final slot in slots.wanted)
              _SlotTile(
                slot: slot,
                sending: _sending.containsKey(slot.id),
                enabled: storage.ready,
                onTap: () => _choose(slot, slots.wanted),
              ),
          ],
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

    final Widget leading = sending
        ? const SizedBox(width: 48, height: 48, child: LoadingState())
        : RowThumb(
            size: 48,
            image: taken ? NetworkImage(slot.url!) : null,
            icon: taken ? null : Icons.photo_camera_outlined,
          );

    final StatusBadge state = sending
        ? const StatusBadge('Sending…')
        : taken
            ? const StatusBadge('Photographed', tone: BadgeTone.success, icon: Icons.check)
            : const StatusBadge('Still to be taken', tone: BadgeTone.warning);

    return AppListRow(
      title: slot.label,
      leading: leading,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          state,
          const SizedBox(width: 6),
          Icon(
            taken ? Icons.more_horiz : Icons.add_a_photo_outlined,
            color: enabled ? p.text : p.textMuted,
          ),
        ],
      ),
      onTap: sending || !enabled ? null : onTap,
    );
  }
}
