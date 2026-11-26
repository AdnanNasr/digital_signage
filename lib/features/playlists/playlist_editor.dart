import 'package:flutter/material.dart';

import '../../models/media_file.dart';
import '../../models/playlist.dart';

class PlaylistEditor extends StatefulWidget {
  const PlaylistEditor({super.key, required this.media, this.playlist});
  final List<MediaFile> media;
  final SavedPlaylist? playlist;

  @override
  State<PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<PlaylistEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final List<String> _items;
  late bool _loop;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.playlist?.name ?? '');
    _duration = TextEditingController(
      text: '${widget.playlist?.imageDuration ?? 10}',
    );
    _items = [...?widget.playlist?.items];
    _loop = widget.playlist?.loop ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _move(int index, int offset) => setState(() {
    final item = _items.removeAt(index);
    _items.insert(index + offset, item);
  });

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      PlaylistDraft(
        name: _name.text.trim(),
        items: [..._items],
        imageDuration: int.parse(_duration.text),
        loop: _loop,
        revision: widget.playlist?.revision ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.media
        .where((file) => !_items.contains(file.id))
        .toList();
    return AlertDialog(
      title: Text(
        widget.playlist == null
            ? 'Neue Wiedergabeliste'
            : 'Wiedergabeliste bearbeiten',
      ),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Form(
          key: _form,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('playlist-name'),
                      controller: _name,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Bitte einen Namen eingeben.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('image-duration'),
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bilddauer in Sekunden',
                        helperText: 'Videos laufen bis zum Ende.',
                      ),
                      validator: (value) {
                        final duration = int.tryParse(value ?? '');
                        return duration == null ||
                                duration < 1 ||
                                duration > 3600
                            ? 'Bitte 1 bis 3600 Sekunden eingeben.'
                            : null;
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatisch wiederholen'),
                      value: _loop,
                      onChanged: (value) => setState(() => _loop = value),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Dateien in dieser Reihenfolge',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (available.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey('add-media-${_items.length}'),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Datei hinzufügen',
                        ),
                        items: available
                            .map(
                              (file) => DropdownMenuItem(
                                value: file.id,
                                child: Text(
                                  file.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id != null) setState(() => _items.add(id));
                        },
                      ),
                    if (widget.media.isEmpty)
                      const Text(
                        'Laden Sie zuerst Bilder oder Videos unter Medien hoch.',
                      ),
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Noch keine Dateien hinzugefügt.'),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final name = _items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: '$name nach oben',
                                  onPressed: index == 0
                                      ? null
                                      : () => _move(index, -1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: '$name nach unten',
                                  onPressed: index == _items.length - 1
                                      ? null
                                      : () => _move(index, 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                IconButton(
                                  tooltip: '$name aus Liste entfernen',
                                  onPressed: () =>
                                      setState(() => _items.removeAt(index)),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
