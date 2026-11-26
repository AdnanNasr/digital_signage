import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/display_settings.dart';
import '../../providers/display_settings_provider.dart';
import 'display_selectors.dart';

class DisplaySettingsPage extends ConsumerStatefulWidget {
  const DisplaySettingsPage({super.key, required this.active});
  final bool active;
  @override
  ConsumerState<DisplaySettingsPage> createState() =>
      _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends ConsumerState<DisplaySettingsPage> {
  DisplaySettingsModel? _source;
  String? _output;
  int? _rotation;
  String _fit = 'contain';
  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant DisplaySettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  void _load() => Future.microtask(() {
    if (mounted) ref.read(displaySettingsProvider.notifier).load();
  });
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(displaySettingsProvider);
    final controller = ref.read(displaySettingsProvider.notifier);
    final settings = state.settings;
    if (settings != null && !identical(settings, _source)) {
      _source = settings;
      _output = settings.output;
      _rotation = settings.rotation;
      _fit = settings.fitMode;
    }
    final selected = settings?.outputs
        .where((o) => o.name == _output)
        .firstOrNull;
    final canRotate = selected != null && selected.rotations.isNotEmpty;
    double? ratio;
    if (selected != null && _rotation != null && selected.rotation != null) {
      ratio = selected.width / selected.height;
      if (_rotation! % 180 != selected.rotation! % 180) ratio = 1 / ratio;
    }
    final error = state.error ?? settings?.error;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Einstellungen', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(
          'Bildschirmeinstellungen',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Ausrichtung und Darstellung direkt auf dem angeschlossenen Bildschirm ändern.',
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: state.busy ? null : controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Aktualisieren'),
          ),
        ),
        if (state.busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(state.message!),
          ),
        if (settings != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Angeschlossener Bildschirm',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (settings.outputs.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'output:$_output:${settings.outputs.map((o) => o.name)}',
                      ),
                      initialValue: _output,
                      isExpanded: true,
                      hint: const Text('Bildschirm auswählen'),
                      items: [
                        for (final output in settings.outputs)
                          DropdownMenuItem(
                            value: output.name,
                            child: Text(output.name),
                          ),
                      ],
                      onChanged: state.busy
                          ? null
                          : (name) => setState(() {
                              _output = name;
                              _rotation = settings.outputs
                                  .firstWhere((o) => o.name == name)
                                  .rotation;
                            }),
                    )
                  else
                    const Text('Der Bildschirm ist nicht erreichbar.'),
                  const SizedBox(height: 12),
                  Text(
                    'Aktuelle Auflösung: ${selected == null ? 'Nicht verfügbar' : '${selected.width} × ${selected.height}'}',
                  ),
                  Text(
                    'Bildschirmausrichtung: ${selected?.rotation == null ? 'Nicht verfügbar' : orientationLabels[selected!.rotation]}',
                  ),
                  Text(
                    'Bildschirmdarstellung: ${fitLabels[settings.fitMode] ?? 'Nicht verfügbar'}',
                  ),
                  const SizedBox(height: 24),
                  DisplayOrientationSelector(
                    value: _rotation,
                    rotations: selected?.rotations ?? [],
                    onChanged: state.busy || !canRotate
                        ? null
                        : (angle) => setState(() => _rotation = angle),
                  ),
                  const SizedBox(height: 20),
                  DisplayFitModeSelector(
                    value: _fit,
                    onChanged: state.busy
                        ? null
                        : (mode) => setState(() => _fit = mode!),
                  ),
                  const SizedBox(height: 12),
                  Text(switch (_fit) {
                    'cover' => 'Das Seitenverhältnis bleibt erhalten. Überstehende Bereiche werden abgeschnitten.',
                    'stretch' => 'Der gesamte Bildschirm wird gefüllt. Der Inhalt kann verzerrt erscheinen.',
                    _ => 'Der gesamte Inhalt bleibt sichtbar. Schwarze Ränder sind möglich.',
                  }),
                  const SizedBox(height: 24),
                  if (ratio != null)
                    DisplayOrientationPreview(
                      rotation: _rotation!,
                      fitMode: _fit,
                      aspectRatio: ratio,
                    ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: state.busy || !fitLabels.containsKey(_fit)
                            ? null
                            : () => controller.apply(
                                _fit,
                                canRotate ? _rotation : null,
                                _output,
                              ),
                        icon: const Icon(Icons.check),
                        label: const Text('Einstellungen übernehmen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy || !canRotate
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Auf Standard zurücksetzen?',
                                    ),
                                    content: const Text(
                                      'Querformat (0°) und Einpassen werden angewendet und gespeichert.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Abbrechen'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Zurücksetzen'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  controller.reset(_output);
                                }
                              },
                        icon: const Icon(Icons.restore),
                        label: const Text('Auf Standard zurücksetzen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Änderungen speichern: Nach erfolgreichem Übernehmen werden die Einstellungen automatisch gespeichert. Die Wiedergabe läuft beim Schließen der Verwaltung weiter.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
