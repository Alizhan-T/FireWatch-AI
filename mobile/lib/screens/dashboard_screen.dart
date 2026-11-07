import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/incident.dart';
import '../providers.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'diagnostics_screen.dart';
import 'incident_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _selectedSeverity = 'high';
  String? _selectedCameraId;
  bool _captureFromCamera = false;
  bool _simulating = false;
  DateTime _lastCheck = DateTime.now();

  Future<void> _runSimulation() async {
    HapticFeedback.mediumImpact();
    setState(() => _simulating = true);
    try {
      final inc = await ref.read(apiProvider).simulateFire(
            cameraId: _selectedCameraId,
            severity: _selectedSeverity,
            captureFromCamera: _captureFromCamera,
          );
      refreshAllFireWatchData(ref);
      setState(() => _lastCheck = DateTime.now());
      final showBanner = ref.read(inAppNotificationsProvider);
      PushService.instance.showInAppIncidentBanner(inc, enabled: showBanner);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Simulation failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  void _pickCameraSheet(List<CameraNode> cameras) {
    if (cameras.isEmpty) return;
    HapticFeedback.selectionClick();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select Monitoring Camera'),
        message: const Text('Choose sector camera for DEMO fire simulation'),
        actions: [
          for (final cam in cameras)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _selectedCameraId = cam.id);
                Navigator.pop(ctx);
              },
              child: Text(cam.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _pickSeveritySheet() {
    HapticFeedback.selectionClick();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select Threat Severity'),
        actions: [
          for (final sev in ['low', 'medium', 'high', 'critical'])
            CupertinoActionSheetAction(
              isDestructiveAction: sev == 'critical',
              onPressed: () {
                setState(() => _selectedSeverity = sev);
                Navigator.pop(ctx);
              },
              child: Text(sev.toUpperCase()),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _showManualIncidentDialog() async {
    HapticFeedback.lightImpact();
    final titleCtrl = TextEditingController(text: 'Smoke plume observed');
    final locCtrl = TextEditingController(text: 'Burabay Sector B');
    final latCtrl = TextEditingController(text: '53.0850');
    final lonCtrl = TextEditingController(text: '70.3020');
    final descCtrl = TextEditingController();
    String sev = 'medium';

    try {
      final created = await showModalBottomSheet<Incident>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.secondaryBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Report Manual Incident',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.pop(ctx),
                        child: const AppIcon(
                          CupertinoIcons.xmark_circle_fill,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CupertinoTextField(
                    controller: titleCtrl,
                    placeholder: 'Incident Title',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: locCtrl,
                    placeholder: 'Location / Sector',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: latCtrl,
                          placeholder: 'Latitude',
                          padding: const EdgeInsets.all(13),
                          style: const TextStyle(color: AppColors.textPrimary),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.cardBorder,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoTextField(
                          controller: lonCtrl,
                          placeholder: 'Longitude',
                          padding: const EdgeInsets.all(13),
                          style: const TextStyle(color: AppColors.textPrimary),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.cardBorder,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CupertinoSlidingSegmentedControl<String>(
                    groupValue: sev,
                    backgroundColor: AppColors.background,
                    thumbColor: AppColors.cardElevated,
                    children: const {
                      'low': Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Low', style: TextStyle(fontSize: 12.5)),
                      ),
                      'medium': Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Medium', style: TextStyle(fontSize: 12.5)),
                      ),
                      'high': Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('High', style: TextStyle(fontSize: 12.5)),
                      ),
                      'critical': Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child:
                            Text('Critical', style: TextStyle(fontSize: 12.5)),
                      ),
                    },
                    onValueChanged: (v) {
                      if (v != null) setModalState(() => sev = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: descCtrl,
                    maxLines: 2,
                    placeholder: 'Field Notes (optional)',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      final lat = double.tryParse(latCtrl.text.trim());
                      final lon = double.tryParse(lonCtrl.text.trim());
                      if (titleCtrl.text.trim().isEmpty ||
                          lat == null ||
                          lon == null ||
                          lat < -90 ||
                          lat > 90 ||
                          lon < -180 ||
                          lon > 180) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a valid title and coordinates (-90..90, -180..180)',
                            ),
                          ),
                        );
                        return;
                      }
                      try {
                        final inc = await ref.read(apiProvider).createIncident(
                              title: titleCtrl.text.trim(),
                              lat: lat,
                              lon: lon,
                              severity: sev,
                              locationName: locCtrl.text.trim().isEmpty
                                  ? null
                                  : locCtrl.text.trim(),
                              description: descCtrl.text.trim().isEmpty
                                  ? null
                                  : descCtrl.text.trim(),
                            );
                        if (ctx.mounted) Navigator.pop(ctx, inc);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
                    icon: const AppIcon(
                      CupertinoIcons.checkmark_shield_fill,
                      size: 17,
                      color: Colors.white,
                    ),
                    label: const Text('Save Incident'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (created != null) {
        refreshAllFireWatchData(ref);
        if (!mounted) return;
        Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => IncidentScreen(incident: created)),
        );
      }
    } finally {
      titleCtrl.dispose();
      locCtrl.dispose();
      latCtrl.dispose();
      lonCtrl.dispose();
      descCtrl.dispose();
    }
  }

  void _openDiagnostics() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const DiagnosticsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);
    final incidentsAsync = ref.watch(incidentsProvider);
    final camerasAsync = ref.watch(camerasProvider);
    final readIds = ref.watch(readIncidentsProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final profile = ref.watch(userProfileProvider);
    final conn = ref.watch(backendConnectionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await ref
                    .read(backendConnectionProvider.notifier)
                    .checkHealth(allowAutoFallback: true);
                refreshAllFireWatchData(ref);
                try {
                  await Future.wait([
                    ref.read(statsProvider.future),
                    ref.read(incidentsProvider.future),
                  ]);
                } catch (_) {}
                if (mounted) setState(() => _lastCheck = DateTime.now());
              },
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 1. Header: FireWatch AI + System Status + AI Monitoring + Avatar
                  _buildTopHeader(statsAsync.valueOrNull, profile, conn),
                  const SizedBox(height: 16),

                  // 2. Hero Block: Forest Safety Status
                  statsAsync.when(
                    data: (stats) => IosFadeIn(
                      child: _buildForestSafetyHero(stats),
                    ),
                    loading: () => const IosSkeletonCard(height: 196),
                    error: (err, _) =>
                        _buildConnectionErrorCard(err, serverUrl),
                  ),
                  const SizedBox(height: 20),

                  // 3. 4 Core Metrics + AI Detection Breakdown + Latest Detection
                  statsAsync.maybeWhen(
                    data: (stats) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const IosSectionHeader(
                          title: 'System Overview',
                          icon: CupertinoIcons.square_grid_2x2,
                        ),
                        _buildCoreMetricsGrid(stats),
                        const SizedBox(height: 14),
                        _buildAiDetectionBreakdownCard(stats),
                        const SizedBox(height: 18),
                        _buildQuickActionsRow(),
                        const SizedBox(height: 22),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),

                  // 4. Recent Activity
                  IosSectionHeader(
                    title: 'Recent Activity',
                    icon: CupertinoIcons.bell,
                    actionLabel: 'All Incidents',
                    onAction: () =>
                        ref.read(navigationTabProvider.notifier).setTab(3),
                  ),
                  _buildRecentActivitySection(incidentsAsync, readIds),
                  const SizedBox(height: 24),

                  // 5. Compact Non-Intrusive DEMO Simulation Block
                  _buildDemoSimulationCard(
                    camerasAsync.valueOrNull ?? const [],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(
    SystemStats? stats,
    UserProfile profile,
    BackendConnectionState conn,
  ) {
    final isOfflineDemo = stats?.isOfflineDemo ?? false;
    final isRealAi = stats?.isRealModel ?? false;
    final isBackendUp = stats != null && !isOfflineDemo;
    final initials = profile.name.trim().isNotEmpty
        ? profile.name.trim().substring(0, 1).toUpperCase()
        : 'A';

    final Color statusDotColor = isBackendUp
        ? AppColors.primaryGreen
        : (isOfflineDemo ? AppColors.warningOrange : AppColors.dangerRed);
    final String statusText = isBackendUp
        ? (conn.latencyMs != null
            ? 'Connected · ${conn.latencyMs} ms'
            : 'System Online')
        : (isOfflineDemo ? 'Offline Demo' : 'Backend Disconnected');

    return Row(
      children: [
        const AppIconBadge(
          icon: CupertinoIcons.flame_fill,
          color: AppColors.primaryGreen,
          boxSize: 38,
          iconSize: 20,
          borderRadius: 12,
          showBorder: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openDiagnostics,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FireWatch AI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.iosDisplayFamily,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusDotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        IosStatusPill(
          label: isRealAi ? 'AI MONITORING' : 'AI DEMO',
          color: isRealAi ? AppColors.primaryGreen : AppColors.warningOrange,
          pulsingDot: true,
        ),
        const SizedBox(width: 8),
        IosPressable(
          onTap: _showManualIncidentDialog,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cardBorder, width: 0.5),
            ),
            alignment: Alignment.center,
            child: const AppIcon(
              CupertinoIcons.plus,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IosPressable(
          onTap: () => ref.read(navigationTabProvider.notifier).setTab(4),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.cardElevated,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForestSafetyHero(SystemStats stats) {
    final active = stats.activeIncidents;
    final criticalCount = stats.activeBySeverity['critical'] ?? 0;
    final highCount = stats.activeBySeverity['high'] ?? 0;

    final Color accentColor;
    final String statusHeadline;
    final String dangerLevelLabel;
    final String statusSubtitle;

    if (criticalCount > 0) {
      accentColor = AppColors.dangerRed;
      statusHeadline = 'CRITICAL DANGER';
      dangerLevelLabel = 'Critical';
      statusSubtitle =
          '$active active fire${active == 1 ? '' : 's'} detected ($criticalCount critical)';
    } else if (active > 0) {
      accentColor = AppColors.warningOrange;
      statusHeadline = highCount > 0 ? 'HIGH FIRE RISK' : 'ELEVATED ALERT';
      dangerLevelLabel = highCount > 0 ? 'High' : 'Elevated';
      statusSubtitle =
          '$active active incident${active == 1 ? '' : 's'} under monitoring';
    } else {
      accentColor = AppColors.primaryGreen;
      statusHeadline = 'NORMAL · ALL CLEAR';
      dangerLevelLabel = 'Low / Safe';
      statusSubtitle = 'No active forest fires across monitored sectors';
    }

    final hh = _lastCheck.hour.toString().padLeft(2, '0');
    final mm = _lastCheck.minute.toString().padLeft(2, '0');

    return IosSurfaceCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 22,
      borderColor: accentColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    AppIcon(
                      active > 0
                          ? CupertinoIcons.exclamationmark_shield_fill
                          : CupertinoIcons.checkmark_shield_fill,
                      color: accentColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'FOREST SAFETY STATUS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Last check $hh:$mm',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusHeadline,
                      style: TextStyle(
                        fontFamily: AppTheme.iosDisplayFamily,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusSubtitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.30),
                    width: 0.6,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '$active',
                      style: TextStyle(
                        fontFamily: AppTheme.iosDisplayFamily,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'ACTIVE FIRES',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroMetaItem(
                  label: 'THREAT LEVEL',
                  value: dangerLevelLabel,
                  valueColor: accentColor,
                ),
              ),
              Expanded(
                child: _HeroMetaItem(
                  label: 'AI MODEL',
                  value: stats.isRealModel ? 'YOLOv8n Real' : 'Demo Heuristic',
                  valueColor: stats.isRealModel
                      ? AppColors.primaryGreen
                      : AppColors.warningOrange,
                ),
              ),
              Expanded(
                child: _HeroMetaItem(
                  label: 'VIDEO FEEDS',
                  value: stats.camerasConfigured > 0
                      ? '${stats.camerasConfigured} RTSP'
                      : 'DEMO VIDEO',
                  valueColor: stats.camerasConfigured > 0
                      ? AppColors.statusOk
                      : AppColors.warningOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoreMetricsGrid(SystemStats stats) {
    final demoVideosCount =
        ref.watch(demoVideosProvider).valueOrNull?.length ?? 3;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.52,
      children: [
        _AppleHomeTile(
          icon: CupertinoIcons.flame_fill,
          iconColor: stats.activeIncidents > 0
              ? AppColors.dangerRed
              : AppColors.primaryAccent,
          value: '${stats.activeIncidents}',
          title: 'Active Incidents',
          subtitle: '${stats.totalIncidents} total logged',
          onTap: () => ref.read(navigationTabProvider.notifier).setTab(3),
        ),
        _AppleHomeTile(
          icon: CupertinoIcons.film_fill,
          iconColor: AppColors.primaryAccent,
          value: stats.camerasConfigured > 0
              ? '${stats.camerasConfigured}'
              : '$demoVideosCount',
          title: stats.camerasConfigured > 0 ? 'Real Cameras' : 'Demo Videos',
          subtitle: stats.camerasConfigured > 0
              ? 'Configured RTSP/HLS'
              : 'FFmpeg + YOLOv8n demo',
          onTap: () {
            ref.read(camerasSubTabProvider.notifier).setMode(0);
            ref.read(navigationTabProvider.notifier).setTab(2);
          },
        ),
        _AppleHomeTile(
          icon: CupertinoIcons.viewfinder,
          iconColor: AppColors.lowBlue,
          value: '${stats.totalDetections}',
          title: 'AI Detections',
          subtitle: stats.avgProcessingMs != null
              ? 'Avg ${stats.avgProcessingMs} ms'
              : 'Open AI Scanner',
          onTap: () {
            ref.read(camerasSubTabProvider.notifier).setMode(1);
            ref.read(navigationTabProvider.notifier).setTab(2);
          },
        ),
        _AppleHomeTile(
          icon: CupertinoIcons.scope,
          iconColor: stats.highRiskZones > 0
              ? AppColors.warningOrange
              : AppColors.primaryGreen,
          value: '${stats.highRiskZones}',
          title: 'Risk Zones',
          subtitle: 'Open Live Map',
          onTap: () => ref.read(navigationTabProvider.notifier).setTab(1),
        ),
      ],
    );
  }

  Widget _buildAiDetectionBreakdownCard(SystemStats stats) {
    final latest = stats.latestDetection;
    return IosSurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppIcon(
                CupertinoIcons.sparkles,
                size: 16,
                color: AppColors.primaryAccent,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'YOLOv8n Detection Telemetry',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IosStatusPill(
                label: stats.isRealModel ? 'REAL MODEL' : 'DEMO',
                color: stats.isRealModel
                    ? AppColors.statusOk
                    : AppColors.warningOrange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroMetaItem(
                  label: 'FIRE CONFIRMED',
                  value: '${stats.fireDetections}',
                  valueColor: stats.fireDetections > 0
                      ? AppColors.dangerRed
                      : AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _HeroMetaItem(
                  label: 'SMOKE DETECTED',
                  value: '${stats.smokeDetections}',
                  valueColor: stats.smokeDetections > 0
                      ? AppColors.warningOrange
                      : AppColors.textPrimary,
                ),
              ),
              Expanded(
                child: _HeroMetaItem(
                  label: 'CLEAR SCANS',
                  value: '${stats.clearDetections}',
                  valueColor: AppColors.statusOk,
                ),
              ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                AppIcon(
                  latest.classification == 'none'
                      ? CupertinoIcons.checkmark_seal_fill
                      : CupertinoIcons.flame_fill,
                  size: 14,
                  color: latest.classification == 'none'
                      ? AppColors.statusOk
                      : AppColors.dangerRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Latest: ${latest.classification.toUpperCase()} '
                    '(${(latest.confidence * 100).toStringAsFixed(0)}%) '
                    '${latest.sourceVideoId != null ? "· ${latest.sourceVideoId}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  formatRelativeOrShortTime(latest.createdAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IosSectionHeader(
          title: 'Quick Actions',
          icon: CupertinoIcons.bolt_fill,
        ),
        Row(
          children: [
            Expanded(
              child: _QuickActionChip(
                icon: CupertinoIcons.film_fill,
                color: AppColors.primaryAccent,
                label: 'Demo Video',
                onTap: () {
                  ref.read(camerasSubTabProvider.notifier).setMode(0);
                  ref.read(navigationTabProvider.notifier).setTab(2);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionChip(
                icon: CupertinoIcons.viewfinder,
                color: AppColors.statusOk,
                label: 'Scan Photo',
                onTap: () {
                  ref.read(camerasSubTabProvider.notifier).setMode(1);
                  ref.read(navigationTabProvider.notifier).setTab(2);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionChip(
                icon: CupertinoIcons.plus_circle_fill,
                color: AppColors.warningOrange,
                label: 'Report',
                onTap: _showManualIncidentDialog,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection(
    AsyncValue<List<Incident>> incidentsAsync,
    Set<String> readIds,
  ) {
    return incidentsAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return const IosSurfaceCard(
            padding: EdgeInsets.symmetric(vertical: 26, horizontal: 20),
            child: Column(
              children: [
                AppIconBadge(
                  icon: CupertinoIcons.checkmark_shield_fill,
                  color: AppColors.primaryGreen,
                  boxSize: 44,
                  iconSize: 22,
                  circular: true,
                ),
                SizedBox(height: 10),
                Text(
                  'No Fire Incidents Recorded',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All monitored forest sectors report normal conditions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          );
        }

        final recent = list.take(5).toList();
        return IosSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                _buildRecentIncidentRow(
                  recent[i],
                  isUnread: !readIds.contains(recent[i].id) &&
                      recent[i].status == 'new',
                ),
                if (i < recent.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1),
                  ),
              ],
            ],
          ),
        );
      },
      loading: () => const IosSkeletonCard(height: 120),
      error: (e, _) => IosSurfaceCard(
        child: Text(
          'Failed to load activity: $e',
          style: const TextStyle(color: AppColors.dangerRed, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildRecentIncidentRow(Incident inc, {required bool isUnread}) {
    final sevColor = AppColors.forSeverity(inc.severity);
    return IosPressable(
      onTap: () {
        ref.read(readIncidentsProvider.notifier).markRead(inc.id);
        Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => IncidentScreen(incident: inc)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AppIconBadge(
              icon: CupertinoIcons.flame_fill,
              color: sevColor,
              boxSize: 36,
              iconSize: 18,
              borderRadius: 11,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isUnread)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          inc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 14.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IosStatusPill(
                        label: AppColors.severityLabel(inc.severity),
                        color: sevColor,
                      ),
                      if (inc.isDemo) ...[
                        const SizedBox(width: 6),
                        const IosStatusPill(
                          label: 'DEMO',
                          color: AppColors.warningOrange,
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatRelativeOrShortTime(inc.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const AppIcon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoSimulationCard(List<CameraNode> cameras) {
    if (_selectedCameraId == null && cameras.isNotEmpty) {
      _selectedCameraId = cameras.first.id;
    }
    final selectedCamName = cameras
            .where((c) => c.id == _selectedCameraId)
            .map((c) => c.name)
            .firstOrNull ??
        (cameras.isNotEmpty ? cameras.first.name : 'Default Sector');

    return IosSurfaceCard(
      color: AppColors.secondaryBackground,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              AppIcon(
                CupertinoIcons.lab_flask,
                color: AppColors.textSecondary,
                size: 16,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Scenario Testing & Simulation',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IosStatusPill(
                label: 'DEMO',
                color: AppColors.warningOrange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: IosPressable(
                  onTap: () => _pickCameraSheet(cameras),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(11),
                      border:
                          Border.all(color: AppColors.cardBorder, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const AppIcon(
                          CupertinoIcons.videocam,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            selectedCamName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const AppIcon(
                          CupertinoIcons.chevron_up_chevron_down,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: IosPressable(
                  onTap: _pickSeveritySheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(11),
                      border:
                          Border.all(color: AppColors.cardBorder, width: 0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedSeverity.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.forSeverity(_selectedSeverity),
                          ),
                        ),
                        const AppIcon(
                          CupertinoIcons.chevron_up_chevron_down,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Record 5s stream clip via FFmpeg',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              CupertinoSwitch(
                value: _captureFromCamera,
                activeTrackColor: AppColors.primaryGreen,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _captureFromCamera = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          IosPressable(
            onTap: _simulating ? null : _runSimulation,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.dangerRed.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.dangerRed.withValues(alpha: 0.40),
                  width: 0.7,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_simulating)
                    const CupertinoActivityIndicator(radius: 8)
                  else
                    const AppIcon(
                      CupertinoIcons.flame,
                      color: AppColors.dangerRed,
                      size: 16,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _simulating
                        ? 'Simulating Incident…'
                        : 'SIMULATE FIRE (DEMO)',
                    style: const TextStyle(
                      color: AppColors.dangerRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionErrorCard(Object err, String serverUrl) {
    return IosSurfaceCard(
      borderColor: AppColors.dangerRed.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              AppIcon(
                CupertinoIcons.wifi_exclamationmark,
                color: AppColors.dangerRed,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Backend Disconnected',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.dangerRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Could not reach FastAPI server at $serverUrl.\n'
            'Ensure your iPhone and Mac are on the same Wi-Fi network.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await ref
                      .read(backendConnectionProvider.notifier)
                      .checkHealth(allowAutoFallback: true);
                  refreshAllFireWatchData(ref);
                },
                icon: const AppIcon(
                  CupertinoIcons.refresh,
                  size: 15,
                  color: Color(0xFF041209),
                ),
                label: const Text('Reconnect'),
              ),
              OutlinedButton.icon(
                onPressed: _openDiagnostics,
                icon: const AppIcon(
                  CupertinoIcons.speedometer,
                  size: 15,
                ),
                label: const Text('Diagnostics'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(offlineDemoModeProvider.notifier).set(true);
                  refreshAllFireWatchData(ref);
                },
                icon: const AppIcon(
                  CupertinoIcons.play_circle,
                  size: 15,
                ),
                label: const Text('Offline Demo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetaItem extends StatelessWidget {
  const _HeroMetaItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _AppleHomeTile extends StatelessWidget {
  const _AppleHomeTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosSurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppIconBadge(
                icon: icon,
                color: iconColor,
                boxSize: 34,
                iconSize: 17,
                circular: true,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.iosDisplayFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
