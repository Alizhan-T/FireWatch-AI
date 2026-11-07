import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/incident.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'incident_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _showIncidents = true;
  bool _showCameras = true;
  bool _showRiskZones = true;
  LatLng? _userLocation;
  bool _locating = false;
  String _searchQuery = '';

  Incident? _selectedIncident;
  CameraNode? _selectedCamera;

  static const _defaultCenter = LatLng(48.0, 73.5);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _locateUser() async {
    HapticFeedback.lightImpact();
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission not granted.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = target);
      _mapController.move(target, 11);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get current location: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _selectIncident(Incident inc) {
    HapticFeedback.selectionClick();
    ref.read(readIncidentsProvider.notifier).markRead(inc.id);
    setState(() {
      _selectedIncident = inc;
      _selectedCamera = null;
      _searchQuery = '';
      _searchCtrl.clear();
    });
    _mapController.move(LatLng(inc.lat, inc.lon), 11);
  }

  void _selectCamera(CameraNode cam) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCamera = cam;
      _selectedIncident = null;
      _searchQuery = '';
      _searchCtrl.clear();
    });
    _mapController.move(LatLng(cam.lat, cam.lon), 11);
  }

  @override
  Widget build(BuildContext context) {
    final incidents = ref.watch(incidentsProvider).valueOrNull ?? const [];
    final cameras = ref.watch(camerasProvider).valueOrNull ?? const [];
    final zones = ref.watch(riskZonesProvider).valueOrNull ?? const [];

    final initialCenter = incidents.isNotEmpty
        ? LatLng(incidents.first.lat, incidents.first.lon)
        : (cameras.isNotEmpty
            ? LatLng(cameras.first.lat, cameras.first.lon)
            : _defaultCenter);

    final q = _searchQuery.trim().toLowerCase();
    final filteredIncidents = q.isEmpty
        ? incidents
        : incidents
            .where((i) =>
                i.title.toLowerCase().contains(q) ||
                (i.locationName?.toLowerCase().contains(q) ?? false))
            .toList();
    final filteredCameras = q.isEmpty
        ? cameras
        : cameras
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.id.toLowerCase().contains(q))
            .toList();

    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Edge-to-Edge Apple Maps-style Map Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: incidents.isNotEmpty ? 9.5 : 5.5,
              onTap: (_, __) {
                FocusScope.of(context).unfocus();
                if (_selectedIncident != null || _selectedCamera != null) {
                  setState(() {
                    _selectedIncident = null;
                    _selectedCamera = null;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'kz.alizhan.firewatchai',
              ),
              if (_showRiskZones && zones.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final z in zones)
                      CircleMarker(
                        point: LatLng(z.lat, z.lon),
                        radius: z.radiusM,
                        useRadiusInMeter: true,
                        color: AppColors.forSeverity(z.severity)
                            .withValues(alpha: 0.20),
                        borderColor: AppColors.forSeverity(z.severity),
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
              if (_showCameras && filteredCameras.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final cam in filteredCameras)
                      Marker(
                        point: LatLng(cam.lat, cam.lon),
                        width: 46,
                        height: 46,
                        child: GestureDetector(
                          onTap: () => _selectCamera(cam),
                          child: AnimatedScale(
                            scale: _selectedCamera?.id == cam.id ? 1.18 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primaryGreen,
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryGreen
                                        .withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                CupertinoIcons.videocam_fill,
                                color: AppColors.primaryGreen,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (_showIncidents && filteredIncidents.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final inc in filteredIncidents)
                      Marker(
                        point: LatLng(inc.lat, inc.lon),
                        width: 52,
                        height: 52,
                        child: GestureDetector(
                          onTap: () => _selectIncident(inc),
                          child: AnimatedScale(
                            scale:
                                _selectedIncident?.id == inc.id ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              decoration: BoxDecoration(
                                color: (inc.classification ?? '')
                                            .toLowerCase() ==
                                        'smoke'
                                    ? AppColors.warningOrange
                                    : AppColors.forSeverity(inc.severity),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.forSeverity(inc.severity)
                                        .withValues(alpha: 0.55),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                (inc.classification ?? '').toLowerCase() ==
                                        'smoke'
                                    ? CupertinoIcons.smoke_fill
                                    : CupertinoIcons.flame_fill,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.systemBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.systemBlue.withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. Top Subtle Gradient Scrim for Dynamic Island / Status Bar readability
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 125,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.82),
                      AppColors.background.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Floating Search Bar & Compact Filters (Apple Maps style)
          Positioned(
            top: topPadding + 8,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.cardBorder,
                          width: 0.6,
                        ),
                      ),
                      child: CupertinoSearchTextField(
                        controller: _searchCtrl,
                        placeholder: 'Search sectors, cameras, incidents…',
                        backgroundColor: Colors.transparent,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                        ),
                        placeholderStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        itemColor: AppColors.textSecondary,
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _MapFilterPill(
                        label: 'Fires (${incidents.length})',
                        icon: CupertinoIcons.flame_fill,
                        activeColor: AppColors.dangerRed,
                        selected: _showIncidents,
                        onTap: () =>
                            setState(() => _showIncidents = !_showIncidents),
                      ),
                      const SizedBox(width: 8),
                      _MapFilterPill(
                        label: 'Cameras (${cameras.length})',
                        icon: CupertinoIcons.videocam_fill,
                        activeColor: AppColors.primaryGreen,
                        selected: _showCameras,
                        onTap: () =>
                            setState(() => _showCameras = !_showCameras),
                      ),
                      const SizedBox(width: 8),
                      _MapFilterPill(
                        label: 'Risk Zones (${zones.length})',
                        icon: CupertinoIcons.scope,
                        activeColor: AppColors.warningOrange,
                        selected: _showRiskZones,
                        onTap: () =>
                            setState(() => _showRiskZones = !_showRiskZones),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Floating Right Control Pod (Location + Latest Fire + Refresh)
          Positioned(
            right: 14,
            top: topPadding + 118,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.cardBorder, width: 0.6),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FloatingMapIconButton(
                        icon: CupertinoIcons.location_fill,
                        color: _userLocation != null
                            ? AppColors.systemBlue
                            : AppColors.textPrimary,
                        loading: _locating,
                        onTap: _locateUser,
                      ),
                      Container(
                        width: 28,
                        height: 0.5,
                        color: AppColors.separator,
                      ),
                      if (incidents.isNotEmpty) ...[
                        _FloatingMapIconButton(
                          icon: CupertinoIcons.flame_fill,
                          color: AppColors.dangerRed,
                          onTap: () => _selectIncident(incidents.first),
                        ),
                        Container(
                          width: 28,
                          height: 0.5,
                          color: AppColors.separator,
                        ),
                      ],
                      _FloatingMapIconButton(
                        icon: CupertinoIcons.refresh,
                        color: AppColors.textPrimary,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          refreshAllFireWatchData(ref);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 5. Bottom Apple Maps Object Details Card or Quick Sector Switcher
          Positioned(
            left: 14,
            right: 14,
            bottom: (bottomPadding > 0 ? bottomPadding : 12) + 64,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _selectedIncident != null
                  ? _buildIncidentBottomCard(_selectedIncident!)
                  : (_selectedCamera != null
                      ? _buildCameraBottomCard(_selectedCamera!)
                      : _buildQuickSectorsBar(cameras, incidents)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentBottomCard(Incident inc) {
    final sevColor = AppColors.forSeverity(inc.severity);
    return IosGlassCard(
      key: ValueKey('inc_${inc.id}'),
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      enableBlur: true,
      color: AppColors.background.withValues(alpha: 0.90),
      borderColor: sevColor.withValues(alpha: 0.45),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: sevColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.flame_fill,
                  color: sevColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${inc.locationName ?? "Sector"} · ${inc.lat.toStringAsFixed(4)}, ${inc.lon.toStringAsFixed(4)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => setState(() => _selectedIncident = null),
                child: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              IosStatusPill(
                label: AppColors.severityLabel(inc.severity),
                color: sevColor,
              ),
              IosStatusPill(
                label: AppColors.detectionModeLabel(inc.detectionMode),
                color: inc.detectionMode == 'real_model'
                    ? AppColors.primaryGreen
                    : AppColors.warningOrange,
              ),
              if (inc.confidence != null)
                IosStatusPill(
                  label: '${(inc.confidence! * 100).toStringAsFixed(0)}% CONF',
                  color: AppColors.lowBlue,
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => IncidentScreen(incident: inc),
                  ),
                );
              },
              icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 17),
              label: const Text('Open Incident Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraBottomCard(CameraNode cam) {
    return IosGlassCard(
      key: ValueKey('cam_${cam.id}'),
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      enableBlur: true,
      color: AppColors.background.withValues(alpha: 0.90),
      borderColor: AppColors.primaryGreen.withValues(alpha: 0.45),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.videocam_fill,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cam.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Node ${cam.id} · ${cam.lat.toStringAsFixed(4)}° N, ${cam.lon.toStringAsFixed(4)}° E',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => setState(() => _selectedCamera = null),
                child: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(selectedCameraIdProvider.notifier).select(cam.id);
                    ref.read(camerasSubTabProvider.notifier).setMode(2);
                    ref.read(navigationTabProvider.notifier).setTab(2);
                  },
                  icon: const Icon(CupertinoIcons.play_fill, size: 16),
                  label: const Text('Open Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerRed,
                    side: BorderSide(
                      color: AppColors.dangerRed.withValues(alpha: 0.5),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final inc = await ref
                          .read(apiProvider)
                          .simulateFire(cameraId: cam.id, severity: 'high');
                      refreshAllFireWatchData(ref);
                      if (mounted) _selectIncident(inc);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(CupertinoIcons.flame, size: 16),
                  label: const Text('Simulate (DEMO)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSectorsBar(
    List<CameraNode> cameras,
    List<Incident> incidents,
  ) {
    return Column(
      key: const ValueKey('quick_sectors'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cameras.isEmpty && incidents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.cardBorder, width: 0.6),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_shield_fill,
                        color: AppColors.statusOk,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No active fire markers or configured cameras on map.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  if (incidents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _QuickJumpChip(
                        icon: CupertinoIcons.flame_fill,
                        iconColor: AppColors.dangerRed,
                        label: 'Latest Alert',
                        onTap: () => _selectIncident(incidents.first),
                      ),
                    ),
                  for (final cam in cameras)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _QuickJumpChip(
                        icon: CupertinoIcons.videocam_fill,
                        iconColor: AppColors.primaryGreen,
                        label: cam.name.split('—').first.trim(),
                        onTap: () => _selectCamera(cam),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Map Legend bar
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder, width: 0.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LegendDot(color: AppColors.dangerRed, label: 'Fire'),
                  _LegendDot(color: AppColors.warningOrange, label: 'Smoke'),
                  _LegendDot(color: AppColors.primaryAccent, label: 'Camera'),
                  _LegendDot(color: AppColors.mediumYellow, label: 'Risk Zone'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _MapFilterPill extends StatelessWidget {
  const _MapFilterPill({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.background.withValues(alpha: 0.90)
                  : AppColors.background.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? activeColor.withValues(alpha: 0.65)
                    : AppColors.cardBorder,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13.5,
                  color: selected ? activeColor : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingMapIconButton extends StatelessWidget {
  const _FloatingMapIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: loading ? null : onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: loading
              ? const CupertinoActivityIndicator(radius: 9)
              : Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }
}

class _QuickJumpChip extends StatelessWidget {
  const _QuickJumpChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.cardBorder, width: 0.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
