import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media_file.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/signage_api.dart';
import '../../services/video_picker.dart';

final videoPickerProvider = Provider<Future<VideoUpload?> Function()>(
  (ref) => pickVideo,
);

class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({super.key});

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  List<MediaFile> _files = [];
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _message;
  VideoUpload? _upload;
  double? _progress;

  SignageApi? get _api => ref.read(dashboardProvider.notifier).api;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _upload?.cancel();
    super.dispose();
  }

  void _handleError(ApiException error) {
    if (!mounted) return;
    if (error.statusCode == 401) {
      ref.read(dashboardProvider.notifier).expireSession();
    } else {
      setState(() => _error = error.message);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = _api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await api.media();
      if (mounted) setState(() => _files = files);
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseAndUpload() async {
    if (_working) return;
    final api = _api;
    if (api == null) return;
    final choose = ref.read(videoPickerProvider);
    setState(() {
      _working = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await choose();
      if (file == null) return;
      if (!mounted) {
        file.cancel();
        return;
      }
      if (!RegExp(
        r'\.(mp4|mkv|mov|webm)$',
        caseSensitive: false,
      ).hasMatch(file.name)) {
        throw const ApiException('Erlaubt sind MP4, MKV, MOV und WebM.');
      }
      if (file.size == 0) throw const ApiException('Die Datei ist leer.');
      setState(() {
        _upload = file;
        _progress = 0;
      });
      await api.upload(file, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      setState(() {
        _message = 'Video erfolgreich hochgeladen.';
        _files = [
          ..._files,
          MediaFile(id: file.name, name: file.name, sizeBytes: file.size),
        ]..sort((first, second) => first.name.compareTo(second.name));
      });
      await _load();
      if (mounted) ref.read(dashboardProvider.notifier).refresh();
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _progress = null;
          _upload = null;
        });
      }
    }
  }

  Future<void> _delete(MediaFile file) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Video löschen?'),
          content: Text('„${file.name}“ wird dauerhaft vom Gerät gelöscht.'),
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
      if (confirmed != true || !mounted) return;
      final api = _api;
      if (api == null) return;
      setState(() {
        _error = null;
        _message = null;
      });
      await api.deleteMedia(file.id);
      if (!mounted) return;
      setState(() {
        _files = _files.where((item) => item.id != file.id).toList();
        _message = 'Video erfolgreich gelöscht.';
      });
      ref.read(dashboardProvider.notifier).refresh();
    } on ApiException catch (error) {
      _handleError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEDIENBIBLIOTHEK',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ihre Videos',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ihre Inhalte, übersichtlich organisiert und jederzeit griffbereit.',
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDF1FC),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.cloud_upload_outlined,
                                    color: colors.primary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Neue Videos hinzufügen',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'MP4, MKV, MOV und WebM',
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _working || _loading
                                      ? null
                                      : _chooseAndUpload,
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text('Video hochladen'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _working || _loading
                                      ? null
                                      : _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Dateien aktualisieren'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_progress != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _upload!.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: _progress! < 1 ? _progress : null,
                                semanticsLabel: 'Upload-Fortschritt',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _progress! < 1
                                    ? 'Wird hochgeladen … ${(_progress! * 100).round()} %'
                                    : 'Video wird geprüft …',
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null || _message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            width: double.infinity,
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
                    const SizedBox(height: 20),
                    if (_loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Videos werden geladen',
                      ),
                    if (!_loading && _files.isEmpty && _error == null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.video_library_outlined,
                                size: 44,
                                color: colors.primary,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Noch keine Videos vorhanden. Laden Sie Ihr erstes Video hoch.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_files.isNotEmpty) ...[
                      Text(
                        _files.length == 1
                            ? '1 Video'
                            : '${_files.length} Videos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Videos aus der laufenden Wiedergabe können erst nach dem Stoppen gelöscht werden.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverList.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEDF1FC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.movie_outlined,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: file.name,
                                    child: Text(
                                      file.name,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(file.formattedSize),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '${file.name} löschen',
                              style: IconButton.styleFrom(
                                foregroundColor: colors.error,
                              ),
                              onPressed: _working || _loading
                                  ? null
                                  : () => _delete(file),
                              icon: const Icon(Icons.delete_outline),
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
