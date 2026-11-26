import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media_file.dart';
import '../../models/playlist.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/signage_api.dart';
import 'playlist_editor.dart';

class PlaylistsPage extends ConsumerStatefulWidget {
  const PlaylistsPage({super.key, required this.active});
  final bool active;
  @override
  ConsumerState<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends ConsumerState<PlaylistsPage> {
  List<SavedPlaylist> _playlists = [];
  List<MediaFile> _media = [];
  String? _selectedId;
  String? _error;
  String? _message;
  bool _loading = false;
  bool _working = false;
  SignageApi? get _api => ref.read(dashboardProvider.notifier).api;

  @override
  void initState() {
    super.initState();
    if (widget.active) Future.microtask(_load);
  }

  @override
  void didUpdateWidget(PlaylistsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_working) {
      Future.microtask(_load);
    }
  }

  void _failure(ApiException error) {
    if (!mounted) return;
    if (error.statusCode == 401) {
      ref.read(dashboardProvider.notifier).expireSession();
    } else {
      setState(() => _error = error.message);
    }
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    final api = _api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([api.playlists(), api.media()]);
      if (!mounted) return;
      final collection = values[0] as PlaylistCollection;
      setState(() {
        _playlists = collection.playlists;
        _selectedId = collection.selectedId;
        _media = values[1] as List<MediaFile>;
      });
    } on ApiException catch (error) {
      _failure(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(
    Future<void> Function(SignageApi) action,
    String message,
  ) async {
    if (_working) return;
    final api = _api;
    if (api == null) return;
    setState(() {
      _working = true;
      _error = null;
      _message = null;
    });
    try {
      await action(api);
      if (!mounted) return;
      setState(() => _message = message);
      await _load();
      if (mounted) await ref.read(dashboardProvider.notifier).refresh();
    } on ApiException catch (error) {
      _failure(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit([SavedPlaylist? playlist]) async {
    final draft = await showDialog<PlaylistDraft>(
      context: context,
      builder: (context) => PlaylistEditor(media: _media, playlist: playlist),
    );
    if (draft == null || !mounted) return;
    await _action(
      (api) => api.savePlaylist(draft, id: playlist?.id),
      'Wiedergabeliste gespeichert.',
    );
  }

  Future<void> _delete(SavedPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wiedergabeliste löschen?'),
        content: Text(
          '„${playlist.name}“ wird entfernt. Die Mediendateien bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action(
        (api) => api.deletePlaylist(playlist.id),
        'Wiedergabeliste gelöscht.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(dashboardProvider).status;
    final busy = _working || _loading;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Wiedergabelisten',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bilder und Videos zusammenstellen und die gewünschte Liste starten.',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : () => _edit(),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Neue Liste'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Listen aktualisieren'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Beim Start verwenden',
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  key: const Key('selected-playlist'),
                                  value: _selectedId ?? '',
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('Alle Medien'),
                                    ),
                                    ..._playlists.map(
                                      (item) => DropdownMenuItem(
                                        value: item.id,
                                        child: Text(
                                          item.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (id) => _action(
                                          (api) => api.selectPlaylist(
                                            id == '' ? null : id,
                                          ),
                                          'Auswahl gespeichert.',
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Die Auswahl gilt beim nächsten Start. Mit „Jetzt wiedergeben“ wechseln Sie sofort zur gewünschten Liste.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading || _working) const LinearProgressIndicator(),
                    if (_error != null || _message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _error != null
                                  ? colors.errorContainer
                                  : colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error ?? _message!,
                              style: TextStyle(
                                color: _error != null
                                    ? colors.onErrorContainer
                                    : colors.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!busy && _playlists.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Noch keine Wiedergabelisten vorhanden. Erstellen Sie Ihre erste Liste.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverList.builder(
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final item = _playlists[index];
                  final running =
                      player?.currentPlaylistId == item.id && player!.isActive;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  '${item.items.length} Dateien · Bilder: ${item.imageDuration} s',
                                ),
                                if (_selectedId == item.id)
                                  const Text(
                                    'Ausgewählt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (running)
                                  Text(
                                    player.state == 'paused'
                                        ? 'Pausiert'
                                        : 'Läuft',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.loop
                                  ? 'Wiederholung eingeschaltet'
                                  : 'Einmalige Wiedergabe',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  key: ValueKey('play-${item.id}'),
                                  onPressed: busy || item.items.isEmpty
                                      ? null
                                      : () => _action(
                                          (api) => api.startPlaylist(item.id),
                                          'Wiedergabe gestartet.',
                                        ),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(
                                    running
                                        ? 'Erneut starten'
                                        : 'Jetzt wiedergeben',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: ValueKey('edit-${item.id}'),
                                  onPressed: busy ? null : () => _edit(item),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Bearbeiten'),
                                ),
                                OutlinedButton.icon(
                                  key: ValueKey('delete-${item.id}'),
                                  onPressed: busy || running
                                      ? null
                                      : () => _delete(item),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Liste löschen'),
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
            ),
          ],
        ),
      ),
    );
  }
}
