import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/shop_logo.dart';
import '../../models/player_status.dart';
import '../../providers/dashboard_provider.dart';
import '../media/media_page.dart';
import '../display/display_settings_page.dart';
import '../playlists/playlists_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    if (state.hasSession) return _SignedInDashboard(state: state);
    return Scaffold(
      appBar: AppBar(title: const Text('Digital Signage')),
      body: const SafeArea(child: _ConnectionForm()),
    );
  }
}

class _SignedInDashboard extends ConsumerStatefulWidget {
  const _SignedInDashboard({required this.state});
  final DashboardState state;

  @override
  ConsumerState<_SignedInDashboard> createState() => _SignedInDashboardState();
}

class _SignedInDashboardState extends ConsumerState<_SignedInDashboard> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(dashboardProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        final content = Scaffold(
          appBar: AppBar(
            title: wide
                ? const Text('Arbeitsbereich')
                : const SizedBox(width: 145, child: ShopLogo()),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(),
            ),
            actions: [
              if (_index == 0)
                IconButton(
                  tooltip: 'Aktualisieren',
                  onPressed: widget.state.busy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              IconButton(
                tooltip: 'Abmelden',
                onPressed: controller.disconnect,
                icon: const Icon(Icons.logout_rounded),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _index,
              children: [
                _Overview(state: widget.state),
                const MediaPage(),
                PlaylistsPage(active: _index == 2),
                DisplaySettingsPage(active: _index == 3),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      selectedIcon: Icon(Icons.space_dashboard_rounded),
                      label: 'Übersicht',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.video_library_outlined),
                      selectedIcon: Icon(Icons.video_library_rounded),
                      label: 'Medien',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.playlist_play_outlined,
                        key: Key('playlists-tab'),
                      ),
                      selectedIcon: Icon(Icons.playlist_play),
                      label: 'Listen',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.settings_outlined,
                        key: Key('settings-tab'),
                      ),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Einstellungen',
                    ),
                  ],
                ),
        );
        return Row(
          children: [
            if (wide)
              _DesktopNavigation(
                index: _index,
                onSelected: (index) => setState(() => _index = index),
              ),
            Expanded(key: const ValueKey('workspace'), child: content),
          ],
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: Material(
      color: const Color(0xFF19294E),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: ShopLogo(),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 0, 12, 16),
              child: Text(
                'VERWALTUNG',
                style: TextStyle(
                  color: Color(0xFFA4B5D8),
                  fontSize: 11,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            Expanded(
              child: NavigationRail(
                extended: true,
                minExtendedWidth: 232,
                selectedIndex: index,
                onDestinationSelected: onSelected,
                backgroundColor: Colors.transparent,
                indicatorColor: const Color(0xFF2F4270),
                selectedIconTheme: const IconThemeData(
                  color: Color(0xFFF5CD45),
                ),
                unselectedIconTheme: const IconThemeData(
                  color: Color(0xFFA4B5D8),
                ),
                selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  color: Color(0xFFC3CCE4),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    label: Text('Übersicht'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.video_library_outlined),
                    label: Text('Medien'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(
                      Icons.playlist_play_outlined,
                      key: Key('playlists-tab'),
                    ),
                    label: SizedBox(
                      width: 132,
                      child: Text('Wiedergabelisten', maxLines: 2),
                    ),
                  ),
                  NavigationRailDestination(
                    icon: Icon(
                      Icons.settings_outlined,
                      key: Key('settings-tab'),
                    ),
                    label: Text('Einstellungen'),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF26385E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lan_outlined, color: Color(0xFFF5CD45), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Lokales Netzwerk',
                      style: TextStyle(color: Color(0xFFE6EAF5), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.sizeOf(context).width < 950) ...[
                const Align(child: SizedBox(width: 260, child: ShopLogo())),
                const SizedBox(height: 20),
              ],
              Text(
                'Mit Ihrer Anzeige verbinden',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Geben Sie die Server-Adresse und Ihr Passwort ein.'),
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
                  labelText: 'Passwort',
                  suffixIcon: IconButton(
                    tooltip: _showToken
                        ? 'Passwort verbergen'
                        : 'Passwort anzeigen',
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 8
                    ? 'Das Passwort muss mindestens 8 Zeichen enthalten.'
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
                  state.busy ? 'Verbindung wird hergestellt …' : 'Verbinden',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 950;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8EDF9), Color(0xFFFAFBFE)],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1040 : 460),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: const Color(0xFF19294E),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 280, child: ShopLogo()),
                                  SizedBox(height: 48),
                                  Text(
                                    'Gute Inhalte.\nStarker Auftritt.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 44,
                                      height: 1.12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1.5,
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  Text(
                                    'Ihre Videos und Ihre Anzeige – einfach an einem Ort verwalten.',
                                    style: TextStyle(
                                      color: Color(0xFFBDC9E4),
                                      fontSize: 17,
                                      height: 1.6,
                                    ),
                                  ),
                                  SizedBox(height: 48),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lan_outlined,
                                        size: 18,
                                        color: Color(0xFFF5CD45),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Direkt in Ihrem Netzwerk',
                                          style: TextStyle(
                                            color: Color(0xFFF5CD45),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(child: form),
                        ],
                      )
                    : form,
              ),
            ),
          ),
        );
      },
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
        constraints: const BoxConstraints(maxWidth: 1200),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(
              height: 3,
              child: state.busy ? const LinearProgressIndicator() : null,
            ),
            const SizedBox(height: 20),
            Text(
              'IHRE ANZEIGE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ihre Anzeige im Blick',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Status, Inhalte und Wiedergabe an einem Ort.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF65718A),
              ),
            ),
            const SizedBox(height: 28),
            if (state.error != null) ...[
              _ErrorNotice(message: state.error!),
              const SizedBox(height: 20),
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
                        icon: state.connected
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _InfoCard(
                        title: 'Player-Status',
                        value: status == null
                            ? 'Unbekannt'
                            : status.reachable
                            ? 'Bereit'
                            : 'Nicht erreichbar',
                        icon: Icons.connected_tv_rounded,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _InfoCard(
                        title: 'Verfügbare Medien',
                        value: status?.mediaCount.toString() ?? '–',
                        icon: Icons.video_library_outlined,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _NowPlaying(state: state),
            const SizedBox(height: 24),
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
                    if (status?.mediaCount == 0)
                      const Text(
                        'Noch keine Medien vorhanden. Fügen Sie zuerst Bilder oder Videos hinzu.',
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
                                  status.mediaCount > 0 &&
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
                              ready && status.mediaCount > 0,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Der Status wird automatisch aktualisiert.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    final statusColor = switch (status?.state) {
      'playing' => const Color(0xFFA8E5C0),
      'paused' => const Color(0xFFF4D78F),
      'error' || 'unreachable' => const Color(0xFFFFB4AB),
      _ => const Color(0xFFDBE2F2),
    };
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF243C72), Color(0xFF17284B)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF354C7D),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status?.state == 'playing'
                              ? Icons.play_circle_fill_rounded
                              : Icons.circle,
                          color: statusColor,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            status?.label ?? 'Status unbekannt',
                            style: TextStyle(color: statusColor, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Aktuelle Mediendatei',
                    style: TextStyle(color: Color(0xFFBCCAE6), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    status?.currentFile ??
                        (state.connected
                            ? 'Keine Datei wird wiedergegeben.'
                            : 'Aktuell nicht verfügbar.'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (status?.currentPlaylistName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Wiedergabeliste: ${status!.currentPlaylistName}',
                      style: const TextStyle(
                        color: Color(0xFFBCCAE6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    !state.connected
                        ? 'Die Verbindung zur Anzeige wird wiederhergestellt.'
                        : status?.state == 'playing'
                        ? 'Ihre Inhalte laufen auf der verbundenen Anzeige.'
                        : status?.state == 'paused'
                        ? 'Die Wiedergabe ist pausiert und kann fortgesetzt werden.'
                        : 'Starten Sie die Wiedergabe über die Steuerung unten.',
                    style: const TextStyle(
                      color: Color(0xFFBCCAE6),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 600) ...[
              const SizedBox(width: 32),
              Container(
                width: 150,
                height: 140,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF304B83),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF4B6597)),
                ),
                child: const Icon(
                  Icons.connected_tv_rounded,
                  size: 72,
                  color: Color(0xFFF5CD45),
                ),
              ),
            ],
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF1FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFF65718A)),
                ),
                const SizedBox(height: 6),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
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
