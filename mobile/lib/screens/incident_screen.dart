import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/incident.dart';
import '../providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';

class IncidentScreen extends ConsumerStatefulWidget {
  const IncidentScreen({super.key, required this.incident});
  final Incident incident;

  @override
  ConsumerState<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends ConsumerState<IncidentScreen> {
  late Incident _inc;
  VideoPlayerController? _video;
  Object? _videoError;
  bool _updatingStatus = false;

  bool get _isVideo =>
      _inc.mediaUrl != null &&
      (_inc.mediaType == 'video' || _inc.mediaUrl!.endsWith('.mp4'));

  @override
  void initState() {
    super.initState();
    _inc = widget.incident;
    _initMedia();
  }

  void _initMedia() {
    if (_isVideo && _inc.mediaUrl != null && _inc.mediaUrl!.isNotEmpty) {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(_inc.mediaUrl!),
        httpHeaders: ngrokHeaders,
      );
      _video = ctrl;
      ctrl.initialize().then((_) {
        ctrl
          ..setLooping(true)
          ..setVolume(0)
          ..play();
        if (mounted) setState(() {});
      }).catchError((Object e) {
        if (mounted) setState(() => _videoError = e);
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_updatingStatus || _inc.status == newStatus) return;
    HapticFeedback.mediumImpact();
    setState(() => _updatingStatus = true);
    try {
      final updated =
          await ref.read(apiProvider).updateIncidentStatus(_inc.id, newStatus);
      refreshAllFireWatchData(ref);
      setState(() => _inc = updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status updated to ${AppColors.statusLabel(newStatus)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Failed to update status: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _call112() async {
    HapticFeedback.heavyImpact();
    final uri = Uri.parse('tel:112');
    final canCall = await canLaunchUrl(uri);
    if (canCall) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dialing tel:112 is only available on a physical iPhone.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteIncident() async {
    HapticFeedback.mediumImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Incident?'),
        content: Text(
          'Remove "${_inc.title}" from the SQLite database?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiProvider).deleteIncident(_inc.id);
      refreshAllFireWatchData(ref);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Failed to delete incident: $e'),
        ),
      );
    }
  }

  Future<void> _showReportActionSheet() async {
    HapticFeedback.lightImpact();
    final coords =
        '${_inc.lat.toStringAsFixed(5)}, ${_inc.lon.toStringAsFixed(5)}';
    final summary = 'FireWatch AI Incident Report\n'
        'ID: ${_inc.id}\n'
        'Title: ${_inc.title}\n'
        'Location: ${_inc.locationName ?? "N/A"} ($coords)\n'
        'Severity: ${_inc.severity.toUpperCase()}\n'
        'Detection Mode: ${AppColors.detectionModeLabel(_inc.detectionMode)}\n'
        'Confidence: ${_inc.confidence != null ? "${(_inc.confidence! * 100).toStringAsFixed(1)}%" : "N/A (Simulated/Manual)"}\n'
        'Timestamp: ${_inc.createdAt.toIso8601String()}';

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Incident Dispatch & Report'),
        message: Text(summary),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _call112();
            },
            child: const Text('Call Emergency Services (112)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: summary));
              if (ctx.mounted) Navigator.pop(ctx);
              await _updateStatus('acknowledged');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Report copied to clipboard & marked Acknowledged',
                    ),
                  ),
                );
              }
            },
            child: const Text('Copy Brief & Mark Acknowledged'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _deleteIncident();
            },
            child: const Text('Delete Incident'),
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

  @override
  Widget build(BuildContext context) {
    final sevColor = AppColors.forSeverity(_inc.severity);
    final point = LatLng(_inc.lat, _inc.lon);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Top ambient glow matching threat severity
          Positioned(
            top: -100,
            left: -50,
            right: -50,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.3),
                    radius: 0.85,
                    colors: [
                      sevColor.withValues(alpha: 0.22),
                      AppColors.background.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Native iOS Navigation Bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                            Icon(
                              CupertinoIcons.chevron_back,
                              color: AppColors.primaryGreen,
                              size: 22,
                            ),
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
                      const Text(
                        'Incident Details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(6),
                        minimumSize: Size.zero,
                        onPressed: _showReportActionSheet,
                        child: const Icon(
                          CupertinoIcons.share,
                          color: AppColors.primaryGreen,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                    children: [
                      // 1. Large Threat Level Hero Card (Apple Weather style)
                      IosGlassCard(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 26,
                        borderColor: sevColor.withValues(alpha: 0.45),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IosStatusPill(
                                  label:
                                      '${AppColors.severityLabel(_inc.severity)} THREAT',
                                  color: sevColor,
                                  pulsingDot: true,
                                  solid: true,
                                ),
                                Row(
                                  children: [
                                    if (_inc.isDemo) ...[
                                      const IosStatusPill(
                                        label: 'DEMO',
                                        color: AppColors.warningOrange,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    IosStatusPill(
                                      label: AppColors.statusLabel(_inc.status)
                                          .toUpperCase(),
                                      color: _inc.isActive
                                          ? AppColors.primaryGreen
                                          : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _inc.title,
                              style: const TextStyle(
                                fontFamily: AppTheme.iosDisplayFamily,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.location_solid,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _inc.locationName ?? 'Forest Monitoring Sector',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_inc.description != null &&
                                _inc.description!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                _inc.description!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Photo or 5s Video Card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(24),
                          border:
                              Border.all(color: AppColors.cardBorder, width: 0.7),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio:
                                  (_video != null && _video!.value.isInitialized)
                                      ? _video!.value.aspectRatio
                                      : 16 / 9,
                              child: _buildMediaContent(sevColor),
                            ),
                            if (_inc.mediaNote != null &&
                                _inc.mediaNote!.isNotEmpty)
                              Container(
                                color: AppColors.card,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Text(
                                  _inc.mediaNote!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Telemetry 2x2 Grid (Coordinates, Source, AI Confidence, Time)
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.85,
                        children: [
                          _TelemetryTile(
                            icon: CupertinoIcons.compass,
                            label: 'COORDINATES',
                            value:
                                '${_inc.lat.toStringAsFixed(4)}° N\n${_inc.lon.toStringAsFixed(4)}° E',
                          ),
                          _TelemetryTile(
                            icon: CupertinoIcons.sparkles,
                            label: 'DETECTION SOURCE',
                            value:
                                '${AppColors.detectionModeLabel(_inc.detectionMode)}\n${(_inc.classification ?? "fire").toUpperCase()}',
                          ),
                          _TelemetryTile(
                            icon: CupertinoIcons.gauge,
                            label: 'AI CONFIDENCE',
                            value: _inc.confidence != null
                                ? '${(_inc.confidence! * 100).toStringAsFixed(1)}%'
                                : (_inc.isDemo ? 'Simulated' : 'Manual'),
                            valueColor: _inc.confidence != null
                                ? sevColor
                                : AppColors.textPrimary,
                          ),
                          _TelemetryTile(
                            icon: CupertinoIcons.clock,
                            label: 'DETECTED AT',
                            value: _inc.createdAt
                                .toString()
                                .substring(0, 19)
                                .replaceFirst(' ', '\n'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 4. Status Action Buttons: Acknowledge, Resolve, False Alarm
                      const IosSectionHeader(
                        title: 'Response Status',
                        icon: CupertinoIcons.shield_lefthalf_fill,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusActionButton(
                              label: 'Acknowledge',
                              icon: CupertinoIcons.eye_fill,
                              selected: _inc.status == 'acknowledged',
                              activeColor: AppColors.warningOrange,
                              onTap: () => _updateStatus('acknowledged'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatusActionButton(
                              label: 'Resolve',
                              icon: CupertinoIcons.checkmark_circle_fill,
                              selected: _inc.status == 'resolved',
                              activeColor: AppColors.primaryGreen,
                              onTap: () => _updateStatus('resolved'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatusActionButton(
                              label: 'False Alarm',
                              icon: CupertinoIcons.xmark_circle_fill,
                              selected: _inc.status == 'false_alarm',
                              activeColor: AppColors.textSecondary,
                              onTap: () => _updateStatus('false_alarm'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 5. Apple Maps-style Map Preview Card
                      const IosSectionHeader(
                        title: 'Sector Map',
                        icon: CupertinoIcons.map_fill,
                      ),
                      Container(
                        height: 210,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.cardBorder,
                            width: 0.7,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: point,
                            initialZoom: 11.5,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'kz.alizhan.firewatchai',
                            ),
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: point,
                                  radius:
                                      _inc.severity == 'critical' ? 2500 : 1500,
                                  useRadiusInMeter: true,
                                  color: sevColor.withValues(alpha: 0.22),
                                  borderColor: sevColor,
                                  borderStrokeWidth: 2,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: point,
                                  width: 48,
                                  height: 48,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: sevColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.2,
                                      ),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.flame_fill,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 6. Emergency Call 112 & Report Buttons
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.dangerRed,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                              onPressed: _call112,
                              icon: const Icon(
                                CupertinoIcons.phone_fill,
                                size: 18,
                              ),
                              label: const Text('Call 112'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                              onPressed: _showReportActionSheet,
                              icon: const Icon(
                                CupertinoIcons.doc_text,
                                size: 17,
                              ),
                              label: const Text('Report'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(Color sevColor) {
    if (_inc.mediaUrl == null || _inc.mediaUrl!.isEmpty) {
      return Container(
        color: AppColors.secondaryBackground,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.flame_fill, color: sevColor, size: 42),
              const SizedBox(height: 8),
              const Text(
                'Telemetry Incident Record',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'No external media clip attached',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_isVideo) {
      if (_videoError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Video stream unavailable:\n$_videoError',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }
      final ctrl = _video;
      if (ctrl == null || !ctrl.value.isInitialized) {
        return const Center(child: CupertinoActivityIndicator(radius: 14));
      }
      return GestureDetector(
        onTap: () => setState(
          () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(ctrl),
            Positioned(
              left: 12,
              top: 12,
              child: IosStatusPill(
                label: _inc.isDemo ? 'DEMO CLIP' : 'REC 5s',
                color: AppColors.dangerRed,
                pulsingDot: true,
                solid: true,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: VideoProgressIndicator(ctrl, allowScrubbing: true),
            ),
          ],
        ),
      );
    }

    return Image.network(
      _inc.mediaUrl!,
      headers: ngrokHeaders,
      fit: BoxFit.cover,
      loadingBuilder: (ctx, child, progress) => progress == null
          ? child
          : const Center(child: CupertinoActivityIndicator(radius: 14)),
      errorBuilder: (_, e, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Could not load image:\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return IosSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.22)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.7)
                : AppColors.cardBorder,
            width: selected ? 1.1 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? activeColor : AppColors.textSecondary,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
