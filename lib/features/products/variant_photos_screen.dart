import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';

/// Capture PRODUCT photos per COLOUR variant and (optionally) per photo-guide
/// slot (Pallu / Body / Border …). Saves to the shared DB via the colour-photos
/// API, so the web portal and the AI generation both read them.
///
/// This is distinct from the design-level Photo Guide, which only holds SAMPLE
/// reference images and has no colour.
class VariantPhotosScreen extends ConsumerStatefulWidget {
  const VariantPhotosScreen({super.key, required this.categoryId, required this.designName});

  final String categoryId;
  final String designName;

  @override
  ConsumerState<VariantPhotosScreen> createState() => _VariantPhotosScreenState();
}

class _VariantPhotosScreenState extends ConsumerState<VariantPhotosScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<String> _colours = [];
  List<Map<String, dynamic>> _slots = [];
  // colorKey -> list of { id, data, slotId, slotLabel, ... }
  final Map<String, List<Map<String, dynamic>>> _photos = {};

  String _ck(String c) => c.trim().toLowerCase();
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final coloursData = await _api.get('/categories/${widget.categoryId}/colours');
      final colours = ((coloursData as List?) ?? [])
          .map((e) => ((e as Map)['colour'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final slotsData = await _api.get('/categories/${widget.categoryId}/photo-slots');
      final slots = ((slotsData as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();

      _photos.clear();
      for (final c in colours) {
        _photos[_ck(c)] = await _fetchColour(c);
      }
      if (!mounted) return;
      setState(() {
        _colours = colours;
        _slots = slots;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchColour(String colour) async {
    final ph = await _api.get('/categories/${widget.categoryId}/colour-photos', query: {'colour': colour});
    return ((ph as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> _reloadColour(String colour) async {
    final list = await _fetchColour(colour);
    if (!mounted) return;
    setState(() => _photos[_ck(colour)] = list);
  }

  void _captureSheet(String colour, {String? slotId}) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pick(colour, slotId, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _pick(colour, slotId, ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pick(String colour, String? slotId, ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (x == null) return;
      final data = base64Encode(await x.readAsBytes());
      setState(() => _busy = true);
      await _api.post('/categories/${widget.categoryId}/colour-photos', body: {
        'colour': colour,
        'slotId': ?slotId,
        'data': data,
      });
      await _reloadColour(colour);
      if (mounted) showOk(context, 'Photo added.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String colour, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.delete('/colour-photos/$id');
      await _reloadColour(colour);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product photos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.designName,
                  style: TextStyle(color: context.p.onAppBar.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_colours.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No colours yet — tag a piece in a colour first, then add its photos here.',
              textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
        ),
      );
    }
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Photos are saved per colour. Tap a shot to capture it — every piece of that colour uses these photos.',
              style: TextStyle(fontSize: 12, color: context.p.textSecondary, height: 1.35),
            ),
          ),
          for (final colour in _colours) _colourCard(context, colour),
        ],
      ),
      if (_busy)
        const Positioned.fill(
          child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator())),
        ),
    ]);
  }

  Widget _colourCard(BuildContext context, String colour) {
    final photos = _photos[_ck(colour)] ?? const [];
    final bySlot = <String, Map<String, dynamic>>{};
    for (final p in photos) {
      final sid = p['slotId'] as String?;
      if (sid != null) bySlot[sid] = p;
    }
    final slotIds = _slots.map((s) => s['id'] as String).toSet();
    final extras = photos.where((p) => p['slotId'] == null || !slotIds.contains(p['slotId'])).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.palette_outlined, size: 16, color: context.p.primary),
            const SizedBox(width: 6),
            Text(colour, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${photos.length} photo${photos.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final s in _slots)
              _tile(
                context,
                label: s['label'] as String,
                required: s['required'] == true,
                photo: bySlot[s['id'] as String],
                onCapture: () => _captureSheet(colour, slotId: s['id'] as String),
                onDelete: (id) => _delete(colour, id),
              ),
            for (final e in extras)
              _tile(
                context,
                label: _slots.isNotEmpty ? 'Extra' : 'Photo',
                required: false,
                photo: e,
                onCapture: () {},
                onDelete: (id) => _delete(colour, id),
              ),
            _tile(
              context,
              label: _slots.isNotEmpty ? 'Add extra' : 'Add photo',
              required: false,
              photo: null,
              onCapture: () => _captureSheet(colour),
              onDelete: (_) {},
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required bool required,
    required Map<String, dynamic>? photo,
    required VoidCallback onCapture,
    required void Function(String id) onDelete,
  }) {
    const double size = 96;
    if (photo != null) {
      final data = (photo['data'] ?? '') as String;
      return SizedBox(
        width: size,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(base64Decode(data), width: size, height: size, fit: BoxFit.cover),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                icon: const Icon(Icons.cancel, size: 20),
                color: context.p.danger,
                onPressed: () => onDelete(photo['id'] as String),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: context.p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
    }
    return SizedBox(
      width: size,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onCapture,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: context.p.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.p.primary.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Icon(Icons.add_a_photo_outlined, color: context.p.primary),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 11, color: context.p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (required) Text(' *', style: TextStyle(fontSize: 11, color: context.p.primary)),
        ]),
      ]),
    );
  }
}
