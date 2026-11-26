import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/player_status.dart';
import '../../providers/dashboard_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final controller = ref.read(dashboardProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(state.hasSession ? 'Übersicht' : 'Digital Signage'),
        actions: state.hasSession
            ? [
                IconButton(
                  tooltip: 'Aktualisieren',
                  onPressed: state.busy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Abmelden',
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.logout),
                ),
                const SizedBox(width: 12),
              ]
            : null,
      ),
      body: SafeArea(
        child: state.hasSession
            ? _Overview(state: state)
            : const _ConnectionForm(),
      ),
    );
  }
}

class _ConnectionForm extends ConsumerStatefulWidget {
  const _ConnectionForm();

  @override
  ConsumerState<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends ConsumerState<_ConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _address;
  final _token = TextEditingController();
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    const configured = String.fromEnvironment('API_BASE_URL');
    _address = TextEditingController(
      text: configured.isNotEmpty
          ? configured
          : kIsWeb
          ? Uri.base.origin
          : 'http://127.0.0.1:8000',
    );
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  void _connect() {
    if (_formKey.currentState!.validate()) {
      ref
          .read(dashboardProvider.notifier)
          .connect(Uri.parse(_address.text.trim()), _token.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.connected_tv, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      'Mit Ihrer Anzeige verbinden',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Geben Sie die Server-Adresse und Ihren Zugangsschlüssel ein.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('server-address'),
                      controller: _address,
                      enabled: !state.busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server-Adresse',
                        hintText: 'http://raspberrypi.local',
                      ),
                      validator: (value) {
                        final uri = Uri.tryParse(value?.trim() ?? '');
                        if (uri == null ||
                            !['http', 'https'].contains(uri.scheme) ||
                            uri.host.isEmpty ||
                            uri.userInfo.isNotEmpty ||
                            (uri.path.isNotEmpty && uri.path != '/') ||
                            uri.hasQuery ||
                            uri.hasFragment) {
                          return 'Bitte eine gültige Server-Adresse eingeben.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('access-token'),
                      controller: _token,
                      enabled: !state.busy,
                      obscureText: !_showToken,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!state.busy) _connect();
                      },
                      decoration: InputDecoration(
                        labelText: 'Zugangsschlüssel',
                        suffixIcon: IconButton(
                          tooltip: _showToken
                              ? 'Schlüssel verbergen'
                              : 'Schlüssel anzeigen',
                          onPressed: () =>
                              setState(() => _showToken = !_showToken),
                          icon: Icon(
                            _showToken
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 32
                          ? 'Der Schlüssel muss mindestens 32 Zeichen enthalten.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    if (state.error != null) ...[
                      _ErrorNotice(message: state.error!),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: state.busy ? null : _connect,
                      icon: state.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        state.busy
                            ? 'Verbindung wird hergestellt …'
                            : 'Verbinden',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = state.status;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(
              height: 4,
              child: state.busy ? const LinearProgressIndicator() : null,
            ),
            const SizedBox(height: 20),
            Text(
              'Ihre Anzeige im Blick',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Der Status wird automatisch aktualisiert.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (state.error != null) ...[
              _ErrorNotice(message: state.error!),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 650
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: _InfoCard(
                        title: 'Server-Verbindung',
                        value: state.connected ? 'Verbunden' : 'Unterbrochen',
                        icon: state.connected ? Icons.wifi : Icons.wifi_off,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _InfoCard(
                        title: 'Wiedergabestatus',
                        value: status?.label ?? 'Unbekannt',
                        icon: status?.state == 'playing'
                            ? Icons.play_circle_outline
                            : Icons.tv,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _InfoCard(
                        title: 'Verfügbare Videos',
                        value: status?.videoCount.toString() ?? '–',
                        icon: Icons.video_library_outlined,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktuelle Mediendatei',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      status?.currentFile ??
                          (state.connected
                              ? 'Keine Datei wird wiedergegeben.'
                              : 'Aktuell nicht verfügbar.'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (state.connected &&
                        status != null &&
                        !status.reachable) ...[
                      const SizedBox(height: 12),
                      Text(
                        status.state == 'stopped'
                            ? 'Der Player ist noch nicht gestartet.'
                            : 'Der Player ist nicht erreichbar. Starten Sie ihn erneut.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wiedergabe steuern',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (status?.videoCount == 0)
                      const Text(
                        'Noch keine Videos vorhanden. Fügen Sie zuerst Videos hinzu.',
                      ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 760
                            ? 3
                            : constraints.maxWidth >= 440
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        final ready =
                            state.connected && !state.busy && status != null;
                        final active =
                            ready && status.isActive && status.reachable;
                        Widget button(
                          String label,
                          IconData icon,
                          PlayerCommand command,
                          bool enabled, {
                          bool primary = false,
                        }) {
                          void send() => ref
                              .read(dashboardProvider.notifier)
                              .command(command);
                          return SizedBox(
                            width: width,
                            child: primary
                                ? FilledButton.icon(
                                    onPressed: enabled ? send : null,
                                    icon: Icon(icon),
                                    label: Text(label),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: enabled ? send : null,
                                    icon: Icon(icon),
                                    label: Text(label),
                                  ),
                          );
                        }

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            button(
                              'Wiedergabe starten',
                              Icons.play_arrow,
                              PlayerCommand.start,
                              ready &&
                                  status.videoCount > 0 &&
                                  !status.isActive,
                              primary: true,
                            ),
                            button(
                              status?.state == 'paused'
                                  ? 'Fortsetzen'
                                  : 'Pause',
                              status?.state == 'paused'
                                  ? Icons.play_arrow
                                  : Icons.pause,
                              status?.state == 'paused'
                                  ? PlayerCommand.resume
                                  : PlayerCommand.pause,
                              active,
                            ),
                            button(
                              'Wiedergabe stoppen',
                              Icons.stop,
                              PlayerCommand.stop,
                              ready,
                            ),
                            button(
                              'Vorherige Datei',
                              Icons.skip_previous,
                              PlayerCommand.previous,
                              active,
                            ),
                            button(
                              'Nächste Datei',
                              Icons.skip_next,
                              PlayerCommand.next,
                              active,
                            ),
                            button(
                              'Neu starten',
                              Icons.restart_alt,
                              PlayerCommand.restart,
                              ready && status.videoCount > 0,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}
