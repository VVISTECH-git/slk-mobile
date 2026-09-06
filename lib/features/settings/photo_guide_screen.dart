import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'settings_providers.dart';

/// Per-category "shot template" editor. The owner defines an ordered list of
/// labelled photo slots (e.g. Front, Back, Neckline), each with an optional
/// reference image, so staff photograph every product in the category the same
/// way. The product form later reads these slots.
class PhotoGuideScreen extends ConsumerWidget {
  const PhotoGuideScreen({super.key, required this.categoryId, required this.categoryName});

  final String categoryId;
  final String categoryName;

  static const _presets = <String, List<String>>{
    'Kurta / dress': ['Front', 'Back', 'Neckline detail', 'Fabric close-up', 'On the hanger'],
    'Saree': ['Full drape', 'Pallu', 'Border', 'Body / weave detail', 'Blouse piece'],
    'Generic garment': ['Front', 'Back', 'Detail close-up'],
  };

  SettingsRepository _repo(WidgetRef ref) => ref.read(settingsRepositoryProvider);

  Future<void> _guard(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(categoryPhotoSlotsProvider(categoryId));
      if (context.mounted) showOk(context, 'Saved.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotsAsync = ref.watch(categoryPhotoSlotsProvider(categoryId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo guide'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(categoryName,
                  style: TextStyle(
                      color: context.p.onAppBar.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
      body: AsyncView<List<Map<String, dynamic>>>(
        value: slotsAsync,
        onRetry: () => ref.invalidate(categoryPhotoSlotsProvider(categoryId)),
        data: (slots) {
          if (slots.isEmpty) return _empty(context, ref);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _sampleBanner(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'A photo checklist for this design. When staff add a product here, they’ll '
                  'be asked to take each shot below — the sample image shows them how.',
                  style: TextStyle(color: context.p.textSecondary, fontSize: 13, height: 1.35),
                ),
              ),
              for (var i = 0; i < slots.length; i++) _slotCard(context, ref, slots[i], i + 1),
            ],
          );
        },
      ),
      floatingActionButton: slotsAsync.maybeWhen(
        data: (slots) => slots.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _editSlot(context, ref, position: slots.length),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add shot'),
              ),
        orElse: () => null,
      ),
    );
  }

  // Clarifies that this screen holds SAMPLE/reference images (colour-agnostic),
  // not the actual product photos — which are captured per colour elsewhere.
  Widget _sampleBanner(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.p.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: context.p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'These are SAMPLE shots — a how-to checklist. The actual product photos '
              'are captured per colour on a product → “Add / manage product photos”.',
              style: TextStyle(fontSize: 12, height: 1.35, color: context.p.textSecondary),
            ),
          ),
        ]),
      );

  Widget _empty(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sampleBanner(context),
        const SizedBox(height: 12),
        Icon(Icons.photo_camera_back_outlined, size: 56, color: context.p.textSecondary),
        const SizedBox(height: 12),
        Text('No photo guide yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.p.text)),
        const SizedBox(height: 8),
        Text(
          'Define the shots staff should take for every product in “$categoryName”. '
          'Start from a template or add your own.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.p.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        Text('Quick start', style: TextStyle(fontWeight: FontWeight.w700, color: context.p.text)),
        const SizedBox(height: 8),
        for (final entry in _presets.entries)
          Card(
            child: ListTile(
              title: Text(entry.key),
              subtitle: Text(entry.value.join(' · '), style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.add),
              onTap: () => _applyPreset(context, ref, entry.value),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _editSlot(context, ref, position: 0),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add a shot manually'),
        ),
      ],
    );
  }

  Widget _slotCard(BuildContext context, WidgetRef ref, Map<String, dynamic> slot, int number) {
    final guide = slot['guide'] as String?;
    final required = slot['required'] == true;
    return Card(
      // Key on the image content so clearing/replacing a reference re-renders the
      // row immediately instead of showing the stale thumbnail.
      key: ValueKey('${slot['id']}:${guide?.hashCode ?? 'none'}'),
      child: ListTile(
        // The image tile IS the capture button — tap to shoot/replace/remove.
        leading: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _quickCapture(context, ref, slot),
          child: SizedBox(
            width: 48,
            height: 48,
            child: guide != null && guide.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(base64Decode(guide), fit: BoxFit.cover),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: context.p.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.add_a_photo_outlined, color: context.p.primary, size: 22),
                  ),
          ),
        ),
        title: Text('$number. ${slot['label']}'),
        subtitle: Text(required ? 'Required' : 'Optional',
            style: TextStyle(fontSize: 12, color: required ? context.p.primary : context.p.textSecondary)),
        // Edit/Delete live in an overflow menu so the destructive action can't be
        // hit by accident (photo actions are on the image tile).
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.p.textSecondary),
          onSelected: (v) {
            if (v == 'edit') _editSlot(context, ref, existing: slot);
            if (v == 'delete') _confirmDelete(context, ref, slot);
          },
          itemBuilder: (menuCtx) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 20, color: menuCtx.p.textSecondary),
                const SizedBox(width: 12),
                const Text('Edit details'),
              ]),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, size: 20, color: menuCtx.p.danger),
                const SizedBox(width: 12),
                Text('Delete shot', style: TextStyle(color: menuCtx.p.danger)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPreset(BuildContext context, WidgetRef ref, List<String> labels) async {
    await _guard(context, ref, () async {
      for (var i = 0; i < labels.length; i++) {
        await _repo(ref).savePhotoSlot(
          categoryId: categoryId,
          label: labels[i],
          required: i == 0, // first shot required by default
          position: i,
        );
      }
    });
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Map<String, dynamic> slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove “${slot['label']}”?'),
        content: const Text('This shot will no longer be shown when adding product photos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      // ignore: use_build_context_synchronously — _guard checks context.mounted itself
      await _guard(context, ref, () => _repo(ref).deletePhotoSlot(slot['id'] as String));
    }
  }

  // Tap the slot image → capture/replace/remove directly, no editor, auto-saved.
  Future<void> _quickCapture(BuildContext context, WidgetRef ref, Map<String, dynamic> slot) async {
    final hasImage = (slot['guide'] as String?)?.isNotEmpty == true;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(hasImage ? 'Retake photo' : 'Take a photo'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickAndSave(context, ref, slot, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pickAndSave(context, ref, slot, ImageSource.gallery);
            },
          ),
          if (hasImage)
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.p.danger),
              title: const Text('Remove photo'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _saveGuide(context, ref, slot, ''); // '' clears
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _pickAndSave(
      BuildContext context, WidgetRef ref, Map<String, dynamic> slot, ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 72);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!context.mounted) return;
      await _saveGuide(context, ref, slot, base64Encode(bytes));
    } catch (e) {
      if (context.mounted) showError(context, 'Could not add image: $e');
    }
  }

  Future<void> _saveGuide(
      BuildContext context, WidgetRef ref, Map<String, dynamic> slot, String guide) async {
    await _guard(context, ref, () => _repo(ref).savePhotoSlot(
          id: slot['id'] as String,
          categoryId: categoryId,
          label: slot['label'] as String,
          required: slot['required'] == true,
          position: slot['position'] as int? ?? 0,
          guide: guide,
        ));
  }

  Future<void> _editSlot(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? existing,
    int position = 0,
  }) async {
    final result = await showModalBottomSheet<_SlotDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SlotEditor(existing: existing),
    );
    if (result == null) return;
    // ignore: use_build_context_synchronously — _guard checks context.mounted itself
    await _guard(context, ref, () => _repo(ref).savePhotoSlot(
          id: existing?['id'] as String?,
          categoryId: categoryId,
          label: result.label,
          required: result.required,
          guide: result.guideChanged ? (result.guide ?? '') : null,
          position: existing?['position'] as int? ?? position,
        ));
  }
}

class _SlotDraft {
  _SlotDraft({required this.label, required this.required, this.guide, required this.guideChanged});
  final String label;
  final bool required;
  final String? guide; // base64, null = cleared
  final bool guideChanged;
}

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?['label'] as String? ?? '');
  late bool _required = widget.existing?['required'] == true;
  late String? _guide = widget.existing?['guide'] as String?;
  bool _guideChanged = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 72,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _guide = base64Encode(bytes);
        _guideChanged = true;
      });
    } catch (e) {
      if (mounted) showError(context, 'Could not add image: $e');
    }
  }

  void _addReference() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guide = _guide;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New shot' : 'Edit shot',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Neckline detail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: guide != null && guide.isNotEmpty
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(base64Decode(guide),
                                width: 72, height: 72, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton(
                              icon: const Icon(Icons.cancel, size: 20),
                              onPressed: () => setState(() {
                                _guide = null;
                                _guideChanged = true;
                              }),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: context.p.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.image_outlined, color: context.p.textSecondary),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addReference,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(guide != null && guide.isNotEmpty ? 'Replace reference' : 'Add reference image'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Required'),
            subtitle: const Text('Staff must take this shot', style: TextStyle(fontSize: 12)),
            value: _required,
            onChanged: (v) => setState(() => _required = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final label = _label.text.trim();
              if (label.isEmpty) {
                showError(context, 'Please enter a label.');
                return;
              }
              Navigator.pop(
                context,
                _SlotDraft(
                  label: label,
                  required: _required,
                  guide: _guide,
                  guideChanged: _guideChanged,
                ),
              );
            },
            child: const Text('Save shot'),
          ),
        ],
      ),
    );
  }
}
