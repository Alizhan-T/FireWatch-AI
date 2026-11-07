import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(backendConnectionProvider.notifier).runFullDiagnostics();
      }
    });
  }

  Future<void> _switchAndProbe(String url) async {
    HapticFeedback.selectionClick();
    await ref.read(serverUrlProvider.notifier).set(url);
    await ref.read(offlineDemoModeProvider.notifier).set(false);
    final report =
        await ref.read(backendConnectionProvider.notifier).runFullDiagnostics();
    if (report.isConnected) {
      refreshAllFireWatchData(ref);
    }
  }

  Future<void> _runDiagnostics() async {
    HapticFeedback.mediumImpact();
    final report =
        await ref.read(backendConnectionProvider.notifier).runFullDiagnostics();
    if (report.isConnected) {
      refreshAllFireWatchData(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(backendConnectionProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final offlineDemo = ref.watch(offlineDemoModeProvider);
    final report = conn.report;

    final statusColor = conn.isConnected
        ? AppColors.primaryGreen
        : (offlineDemo ? AppColors.warningOrange : AppColors.dangerRed);
    final statusLabel = conn.isConnected
        ? 'Connected'
        : (offlineDemo ? 'Disconnected (Offline Demo)' : 'Disconnected');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Native iOS Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          CupertinoIcons.chevron_back,
                          color: AppColors.primaryGreen,
                          size: 20,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Back',
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Backend Diagnostics',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    onPressed: conn.isChecking ? null : _runDiagnostics,
                    child: conn.isChecking
                        ? const CupertinoActivityIndicator(radius: 9)
                        : const AppIcon(
                            CupertinoIcons.refresh,
                            color: AppColors.primaryGreen,
                            size: 19,
                          ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // 1. Live Connection Summary Card
                  IosSurfaceCard(
                    padding: const EdgeInsets.all(18),
                    borderColor: statusColor.withValues(alpha: 0.40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IosStatusPill(
                              label: conn.isConnected
                                  ? 'CONNECTED'
                                  : 'DISCONNECTED',
                              color: statusColor,
                              pulsingDot: true,
                              solid: conn.isConnected,
                            ),
                            if (conn.latencyMs != null)
                              Text(
                                '${conn.latencyMs} ms',
                                style: TextStyle(
                                  fontFamily: AppTheme.iosDisplayFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            AppIconBadge(
                              icon: conn.isConnected
                                  ? CupertinoIcons.checkmark_shield_fill
                                  : CupertinoIcons.wifi_exclamationmark,
                              color: statusColor,
                              boxSize: 42,
                              iconSize: 22,
                              borderRadius: 13,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontFamily: AppTheme.iosDisplayFamily,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    serverUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                conn.isChecking ? null : _runDiagnostics,
                            icon: conn.isChecking
                                ? const CupertinoActivityIndicator(
                                    radius: 9,
                                    color: Colors.black,
                                  )
                                : const AppIcon(
                                    CupertinoIcons.bolt_horizontal_circle_fill,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              conn.isChecking
                                  ? 'Probing FastAPI Endpoints…'
                                  : 'Test Connection & Run Diagnostics',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Core Diagnostic Telemetry Rows
                  const IosSectionHeader(
                    title: 'Connection Telemetry',
                    icon: CupertinoIcons.speedometer,
                  ),
                  IosSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _DiagKeyValueRow(
                          label: 'Server URL',
                          value: serverUrl,
                          icon: CupertinoIcons.link,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'API Status',
                          value: conn.isConnected
                              ? 'Connected (HTTP 200 OK)'
                              : 'Disconnected',
                          valueColor: statusColor,
                          icon: CupertinoIcons.cloud_fill,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'Response Time',
                          value: conn.latencyMs != null
                              ? '${conn.latencyMs} ms'
                              : '—',
                          icon: CupertinoIcons.timer,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'Last Successful Connection',
                          value: conn.lastSuccessAt != null
                              ? formatRelativeOrShortTime(conn.lastSuccessAt!)
                              : 'Never connected on this session',
                          icon: CupertinoIcons.clock_fill,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'AI Detector Mode',
                          value: conn.detectorModelName ??
                              conn.detectorMode ??
                              'Not probed yet',
                          valueColor: conn.detectorMode == 'real_model'
                              ? AppColors.primaryGreen
                              : AppColors.textPrimary,
                          icon: CupertinoIcons.viewfinder,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'FFmpeg Video Engine',
                          value: report == null
                              ? '—'
                              : (report.ffmpegAvailable == true
                                  ? 'Available (Ready)'
                                  : 'Not Detected'),
                          valueColor: report?.ffmpegAvailable == true
                              ? AppColors.statusOk
                              : AppColors.warningOrange,
                          icon: CupertinoIcons.film_fill,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'SQLite Database',
                          value: report == null
                              ? '—'
                              : (report.databaseOk == true
                                  ? 'Healthy (WAL Mode)'
                                  : 'Offline'),
                          valueColor: report?.databaseOk == true
                              ? AppColors.statusOk
                              : AppColors.warningOrange,
                          icon: CupertinoIcons.tray_full_fill,
                        ),
                        const _InsetDivider(),
                        _DiagKeyValueRow(
                          label: 'Environment Mode',
                          value: report?.envMode ??
                              (offlineDemo ? 'offline_demo' : 'local_dev'),
                          icon: CupertinoIcons.desktopcomputer,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Clipboard.setData(ClipboardData(text: serverUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backend URL copied to clipboard'),
                          ),
                        );
                      },
                      icon: const AppIcon(
                        CupertinoIcons.doc_on_doc,
                        size: 14,
                        color: AppColors.primaryAccent,
                      ),
                      label: const Text('Copy Backend URL'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Endpoint Probes (/health, /cameras, /incidents, /stats)
                  const IosSectionHeader(
                    title: 'Endpoint Health Probes',
                    icon: CupertinoIcons.antenna_radiowaves_left_right,
                  ),
                  if (report == null)
                    const IosSkeletonCard(height: 150)
                  else
                    IosSurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _EndpointProbeRow(
                            title: 'Health Check',
                            probe: report.healthProbe,
                          ),
                          const _InsetDivider(),
                          _EndpointProbeRow(
                            title: 'Cameras Endpoint',
                            probe: report.camerasProbe,
                          ),
                          const _InsetDivider(),
                          _EndpointProbeRow(
                            title: 'Incidents Endpoint',
                            probe: report.incidentsProbe,
                          ),
                          const _InsetDivider(),
                          _EndpointProbeRow(
                            title: 'Stats Endpoint',
                            probe: report.statsProbe,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // 4. Quick Network Presets
                  const IosSectionHeader(
                    title: 'Quick Mac Network Targets',
                    icon: CupertinoIcons.wifi,
                  ),
                  IosSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Tap a target below to switch Server URL and immediately test reachability:',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PresetTargetButton(
                          title: 'Mac Wi-Fi LAN (en0)',
                          url: defaultMacLanBackendUrl,
                          selected: serverUrl == defaultMacLanBackendUrl,
                          onTap: () => _switchAndProbe(defaultMacLanBackendUrl),
                        ),
                        const SizedBox(height: 8),
                        _PresetTargetButton(
                          title: 'Mac Virtual LAN (feth512)',
                          url: secondaryMacLanBackendUrl,
                          selected: serverUrl == secondaryMacLanBackendUrl,
                          onTap: () =>
                              _switchAndProbe(secondaryMacLanBackendUrl),
                        ),
                        const SizedBox(height: 8),
                        _PresetTargetButton(
                          title: 'iOS Simulator Loopback',
                          url: defaultSimulatorBackendUrl,
                          selected: serverUrl == defaultSimulatorBackendUrl,
                          onTap: () =>
                              _switchAndProbe(defaultSimulatorBackendUrl),
                        ),
                      ],
                    ),
                  ),

                  // 5. Last Error Details
                  if (conn.lastError != null && conn.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const IosSectionHeader(
                      title: 'Last Error Diagnostic',
                      icon: CupertinoIcons.exclamationmark_triangle,
                    ),
                    IosSurfaceCard(
                      borderColor: AppColors.dangerRed.withValues(alpha: 0.45),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conn.lastError!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.dangerRed,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: conn.lastError!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Error copied to clipboard'),
                                ),
                              );
                            },
                            icon: const AppIcon(
                              CupertinoIcons.doc_on_doc,
                              size: 14,
                            ),
                            label: const Text('Copy Error Log'),
                          ),
                        ],
                      ),
                    ),
                  ],
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

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 48),
      child: Divider(height: 1),
    );
  }
}

class _DiagKeyValueRow extends StatelessWidget {
  const _DiagKeyValueRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = AppColors.textPrimary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppIconBadge(
            icon: icon,
            color: AppColors.textSecondary,
            boxSize: 28,
            iconSize: 15,
            borderRadius: 8,
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointProbeRow extends StatelessWidget {
  const _EndpointProbeRow({
    required this.title,
    required this.probe,
  });

  final String title;
  final EndpointProbeResult probe;

  @override
  Widget build(BuildContext context) {
    final color = probe.ok ? AppColors.primaryGreen : AppColors.dangerRed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBadge(
            icon: probe.ok
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            color: color,
            boxSize: 30,
            iconSize: 16,
            borderRadius: 9,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        '$title (${probe.endpoint})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${probe.latencyMs} ms',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  probe.ok
                      ? 'HTTP ${probe.statusCode ?? 200} · ${probe.summary}'
                      : (probe.error ?? probe.summary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: probe.ok
                        ? AppColors.textSecondary
                        : AppColors.dangerRed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetTargetButton extends StatelessWidget {
  const _PresetTargetButton({
    required this.title,
    required this.url,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen.withValues(alpha: 0.14)
              : AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen.withValues(alpha: 0.55)
                : AppColors.cardBorder,
            width: 0.7,
          ),
        ),
        child: Row(
          children: [
            AppIcon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 16,
              color:
                  selected ? AppColors.primaryGreen : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    url,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
