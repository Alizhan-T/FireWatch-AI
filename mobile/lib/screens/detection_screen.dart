import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/incident.dart';
import '../providers.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'incident_screen.dart';

class DetectionScreen extends ConsumerStatefulWidget {
  const DetectionScreen({super.key});

  @override
  ConsumerState<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends ConsumerState<DetectionScreen> {
  final ImagePicker _picker = ImagePicker();

  // Mode A: DEMO VIDEO state
  String? _selectedDemoVideoId;
  VideoPlayerController? _demoVideoController;
  String? _loadedDemoVideoUrl;
  bool _demoVideoInitializing = false;
  Object? _demoVideoError;
  double _selectedTimestampSec = 1.0;
  bool _extractingFrame = false;
  DetectionResultModel? _videoFrameResult;
  bool _showVideoBoxes = true;
  bool _uploadingVideo = false;

  // Mode B: REAL CAMERAS state
  VideoPlayerController? _realCamController;
  String? _loadedRealCamUrl;
  bool _realCamInitializing = false;
  Object? _realCamError;
  bool _checkingStream = false;

  // Mode C: AI PHOTO SCAN state
  Uint8List? _selectedBytes;
  String _selectedFilename = '';
  DetectionResultModel? _result;
  bool _analyzing = false;
  bool _savingIncident = false;
  bool _loadingSample = false;
  bool _showAnnotated = true;

  @override
  void dispose() {
    _demoVideoController?.removeListener(_onDemoVideoTick);
    _demoVideoController?.dispose();
    _realCamController?.dispose();
    super.dispose();
  }

  void _onDemoVideoTick() {
    final ctrl = _demoVideoController;
    if (ctrl == null || !ctrl.value.isInitialized || !mounted) return;
    if (ctrl.value.isPlaying) {
      final posSec = ctrl.value.position.inMilliseconds / 1000.0;
      if ((posSec - _selectedTimestampSec).abs() >= 0.2) {
        setState(() {
          _selectedTimestampSec = posSec.clamp(
            0.0,
            ctrl.value.duration.inMilliseconds / 1000.0,
          );
        });
      }
    }
  }

  Future<void> _ensureDemoVideoLoaded(DemoVideoModel video) async {
    final targetUrl = video.videoUrl.trim();
    if (targetUrl == _loadedDemoVideoUrl) return;
    _loadedDemoVideoUrl = targetUrl;
    _demoVideoError = null;

    final old = _demoVideoController;
    old?.removeListener(_onDemoVideoTick);
    _demoVideoController = null;
    old?.dispose();

    if (targetUrl.isEmpty) {
      if (mounted) setState(() => _demoVideoInitializing = false);
      return;
    }

    setState(() {
      _demoVideoInitializing = true;
      _selectedTimestampSec = 1.0.clamp(0.0, video.durationSec);
    });

    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(targetUrl),
      httpHeaders: ngrokHeaders,
    );
    _demoVideoController = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      ctrl.addListener(_onDemoVideoTick);
      await ctrl.play();
      if (mounted) {
        setState(() => _demoVideoInitializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _demoVideoError = e;
          _demoVideoInitializing = false;
        });
      }
    }
  }

  Future<void> _extractAndAnalyzeDemoFrame(DemoVideoModel video) async {
    HapticFeedback.mediumImpact();
    final ctrl = _demoVideoController;
    double ts = _selectedTimestampSec;
    if (ctrl != null && ctrl.value.isInitialized) {
      ts = ctrl.value.position.inMilliseconds / 1000.0;
      await ctrl.pause();
    }
    ts = ts.clamp(0.0, video.durationSec > 0.2 ? video.durationSec - 0.15 : 0.0);

    setState(() {
      _extractingFrame = true;
      _selectedTimestampSec = ts;
    });
    try {
      final res = await ref.read(apiProvider).analyzeDemoVideoFrame(
            videoId: video.id,
            timestampSec: ts,
            saveIncident: false,
          );
      refreshAllFireWatchData(ref);
      if (!mounted) return;
      setState(() {
        _videoFrameResult = res;
        _showVideoBoxes = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('FFmpeg / YOLOv8 frame analysis failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _extractingFrame = false);
    }
  }

  Future<void> _uploadCustomDemoVideo() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() => _uploadingVideo = true);
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty ? picked.name : 'custom_demo.mp4';
      final uploaded = await ref.read(apiProvider).uploadDemoVideo(
            bytes: bytes,
            filename: filename,
          );
      ref.invalidate(demoVideosProvider);
      await ref.read(demoVideosProvider.future);
      if (!mounted) return;
      setState(() {
        _selectedDemoVideoId = uploaded.id;
        _loadedDemoVideoUrl = null;
        _videoFrameResult = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded "${uploaded.title}" (DEMO VIDEO)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Video upload failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  void _openFullscreenDemoVideo(DemoVideoModel video) {
    final ctrl = _demoVideoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio,
                    child: VideoPlayer(ctrl),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const IosStatusPill(
                        label: 'DEMO VIDEO · PRERECORDED',
                        color: AppColors.warningOrange,
                        solid: true,
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(ctx),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const AppIcon(
                            CupertinoIcons.fullscreen_exit,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _ensureRealCamLoaded(CameraNode cam) async {
    final targetUrl = cam.url.trim();
    if (targetUrl == _loadedRealCamUrl) return;
    _loadedRealCamUrl = targetUrl;
    _realCamError = null;

    final old = _realCamController;
    _realCamController = null;
    old?.dispose();

    if (targetUrl.isEmpty) {
      if (mounted) setState(() => _realCamInitializing = false);
      return;
    }

    setState(() => _realCamInitializing = true);
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(targetUrl),
      httpHeaders: ngrokHeaders,
    );
    _realCamController = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.play();
      if (mounted) setState(() => _realCamInitializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _realCamError = e;
          _realCamInitializing = false;
        });
      }
    }
  }

  Future<void> _showAddRealCameraDialog() async {
    HapticFeedback.lightImpact();
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final latCtrl = TextEditingController(text: '43.2389');
    final lonCtrl = TextEditingController(text: '76.8897');

    try {
      final created = await showModalBottomSheet<CameraNode>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.secondaryBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add RTSP / HLS Camera',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
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
                const SizedBox(height: 6),
                const Text(
                  'Configure a real IP camera stream URL (RTSP or HLS .m3u8) for future live monitoring.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                CupertinoTextField(
                  controller: nameCtrl,
                  placeholder: 'Camera Name (e.g., Sector North Tower #1)',
                  padding: const EdgeInsets.all(13),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.cardBorder, width: 0.5),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  placeholder:
                      'rtsp://192.168.1.50:554/stream1 or https://.../live.m3u8',
                  padding: const EdgeInsets.all(13),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.cardBorder, width: 0.5),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final url = urlCtrl.text.trim();
                    final lat = double.tryParse(latCtrl.text.trim()) ?? 43.2389;
                    final lon = double.tryParse(lonCtrl.text.trim()) ?? 76.8897;
                    if (name.isEmpty || url.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Enter both a camera name and stream URL'),
                        ),
                      );
                      return;
                    }
                    try {
                      final cam = await ref.read(apiProvider).addCamera(
                            name: name,
                            url: url,
                            lat: lat,
                            lon: lon,
                          );
                      if (ctx.mounted) Navigator.pop(ctx, cam);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.dangerRed,
                            content: Text('Failed to add camera: $e'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const AppIcon(
                    CupertinoIcons.plus_circle_fill,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text('Save Camera Configuration'),
                ),
              ],
            ),
          ),
        ),
      );
      if (created != null) {
        refreshAllFireWatchData(ref);
        ref.read(selectedCameraIdProvider.notifier).select(created.id);
      }
    } finally {
      nameCtrl.dispose();
      urlCtrl.dispose();
      latCtrl.dispose();
      lonCtrl.dispose();
    }
  }

  Future<void> _deleteRealCamera(CameraNode cam) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(apiProvider).deleteCamera(cam.id);
      _loadedRealCamUrl = null;
      _realCamController?.dispose();
      _realCamController = null;
      refreshAllFireWatchData(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Could not remove camera: $e'),
        ),
      );
    }
  }

  Future<void> _checkRealCameraStream(CameraNode cam) async {
    HapticFeedback.mediumImpact();
    setState(() => _checkingStream = true);
    try {
      final checked = await ref.read(apiProvider).checkCamera(cam.id);
      refreshAllFireWatchData(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: checked.isOnline
              ? AppColors.statusOk
              : AppColors.warningOrange,
          content: Text(
            checked.isOnline
                ? 'Stream ONLINE: ${checked.name}'
                : 'Stream OFFLINE: ${checked.lastError ?? "Unreachable"}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Stream check failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingStream = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _selectedBytes = bytes;
        _selectedFilename = file.name.isNotEmpty ? file.name : 'capture.jpg';
        _result = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = source == ImageSource.camera
          ? 'Camera is unavailable on Simulator. Use Photos or Sample below. ($e)'
          : 'Could not pick image: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _loadTestSample(String kind) async {
    HapticFeedback.selectionClick();
    setState(() => _loadingSample = true);
    try {
      final offline = ref.read(offlineDemoModeProvider);
      Uint8List bytes;
      if (offline) {
        bytes = Uint8List.fromList(const [
          0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
          0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB,
          0x00, 0x43, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01,
          0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x09, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00,
          0x3F, 0x00, 0xFB, 0xD5, 0xFF, 0xD9
        ]);
      } else {
        bytes = await ref.read(apiProvider).fetchDemoSampleImage(kind);
      }
      setState(() {
        _selectedBytes = bytes;
        _selectedFilename = 'sample_$kind.jpg';
        _result = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Could not load sample image: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingSample = false);
    }
  }

  Future<void> _analyzeImage() async {
    final bytes = _selectedBytes;
    if (bytes == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _analyzing = true);
    try {
      final res = await ref.read(apiProvider).detectImage(
            bytes: bytes,
            filename: _selectedFilename,
            saveIncident: false,
          );
      refreshAllFireWatchData(ref);
      setState(() {
        _result = res;
        _showAnnotated = res.annotatedImageUrl != null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Analysis failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _saveDetectionAsIncident(
    DetectionResultModel res, {
    DemoVideoModel? demoVideo,
  }) async {
    HapticFeedback.heavyImpact();
    setState(() => _savingIncident = true);
    try {
      var targetLat = demoVideo?.lat ?? 53.0833;
      var targetLon = demoVideo?.lon ?? 70.3000;
      var targetLoc = demoVideo != null
          ? '${demoVideo.locationName} [DEMO VIDEO]'
          : 'AI Detection Monitoring Zone';

      if (demoVideo == null) {
        try {
          final perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 3),
              ),
            );
            targetLat = pos.latitude;
            targetLon = pos.longitude;
            targetLoc = 'iPhone GPS Location';
          }
        } catch (_) {}
      }

      String severity = 'medium';
      if (res.classification == 'fire_smoke') {
        severity = res.confidence >= 0.6 ? 'critical' : 'high';
      } else if (res.classification == 'fire') {
        severity = res.confidence >= 0.5 ? 'high' : 'medium';
      } else if (res.classification == 'smoke') {
        severity = res.confidence >= 0.5 ? 'medium' : 'low';
      } else {
        severity = 'low';
      }

      final clsTitle = switch (res.classification) {
        'fire_smoke' => 'Fire & Smoke Detected',
        'fire' => 'Fire Detected',
        'smoke' => 'Smoke Detected',
        _ => 'Inspection Frame Logged',
      };

      final prefix = demoVideo != null ? 'DEMO VIDEO AI' : 'AI Detection';
      final tsNote = res.frameTimestampSec != null
          ? ' (Frame @ ${res.frameTimestampSec!.toStringAsFixed(1)}s)'
          : '';

      final inc = await ref.read(apiProvider).createIncident(
            title: '$prefix: $clsTitle$tsNote',
            lat: targetLat,
            lon: targetLon,
            severity: severity,
            locationName: targetLoc,
            description:
                'Analyzed by ${res.modelName}$tsNote. Classification: ${res.classification.toUpperCase()}, Confidence: ${(res.confidence * 100).toStringAsFixed(1)}%, Boxes: ${res.boxes.length}.',
            classification: res.classification,
            confidence: res.confidence,
            detectionId: res.id,
          );

      refreshAllFireWatchData(ref);
      final showBanner = ref.read(inAppNotificationsProvider);
      PushService.instance.showInAppIncidentBanner(inc, enabled: showBanner);

      if (!mounted) return;
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => IncidentScreen(incident: inc)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.dangerRed,
          content: Text('Failed to create incident: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingIncident = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subTab = ref.watch(camerasSubTabProvider);
    final demoVideos = ref.watch(demoVideosProvider).valueOrNull ?? const [];
    final cameras = ref.watch(camerasProvider).valueOrNull ?? const [];
    final detectionsHistory =
        ref.watch(detectionsHistoryProvider).valueOrNull ?? const [];
    final stats = ref.watch(statsProvider).valueOrNull;
    final selectedCamId = ref.watch(selectedCameraIdProvider);

    final activeDemoVideo = demoVideos.isEmpty
        ? null
        : demoVideos.firstWhere(
            (v) => v.id == _selectedDemoVideoId,
            orElse: () => demoVideos.first,
          );

    final activeRealCam = cameras.isEmpty
        ? null
        : cameras.firstWhere(
            (c) => c.id == selectedCamId,
            orElse: () => cameras.first,
          );

    if (activeDemoVideo != null && subTab == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureDemoVideoLoaded(activeDemoVideo);
      });
    } else if (activeRealCam != null && subTab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureRealCamLoaded(activeRealCam);
      });
    }

    final headerTitle = switch (subTab) {
      0 => 'Local Video Demo',
      2 => 'Real Cameras (RTSP/HLS)',
      _ => 'AI Image Scanner',
    };
    final headerSubtitle = switch (subTab) {
      0 => 'Prerecorded MP4 · FFmpeg Frame Extraction · YOLOv8n',
      2 => 'External RTSP & HLS Stream Configuration',
      _ => stats?.detectorModelName ?? 'YOLOv8n Fire & Smoke Inference',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.iosDisplayFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headerSubtitle,
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
                const SizedBox(width: 8),
                if (stats != null)
                  IosStatusPill(
                    label: stats.isRealModel ? 'YOLOv8n REAL' : 'DEMO HEURISTIC',
                    color: stats.isRealModel
                        ? AppColors.primaryAccent
                        : AppColors.warningOrange,
                    pulsingDot: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Segmented Control: A. DEMO VIDEO | B. REAL CAMERAS | C. AI PHOTO
            CupertinoSlidingSegmentedControl<int>(
              groupValue: subTab,
              backgroundColor: AppColors.secondaryBackground,
              thumbColor: AppColors.cardElevated,
              children: const {
                0: Padding(
                  padding: EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(CupertinoIcons.film_fill, size: 14),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'DEMO VIDEO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                2: Padding(
                  padding: EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(CupertinoIcons.videocam_fill, size: 14),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'REAL CAMERAS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                1: Padding(
                  padding: EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(CupertinoIcons.viewfinder, size: 14),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'AI PHOTO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              },
              onValueChanged: (v) {
                if (v != null) {
                  HapticFeedback.selectionClick();
                  ref.read(camerasSubTabProvider.notifier).setMode(v);
                }
              },
            ),
            const SizedBox(height: 16),

            if (subTab == 0)
              _buildDemoVideoModeView(
                activeDemoVideo,
                demoVideos,
                detectionsHistory,
              )
            else if (subTab == 2)
              _buildRealCamerasModeView(activeRealCam, cameras)
            else
              _buildAiPhotoScannerView(stats, detectionsHistory),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MODE A: DEMO VIDEO (Local Prerecorded MP4 + FFmpeg + YOLOv8n + History)
  // ===========================================================================
  Widget _buildDemoVideoModeView(
    DemoVideoModel? activeVideo,
    List<DemoVideoModel> videos,
    List<DetectionResultModel> history,
  ) {
    final ctrl = _demoVideoController;
    final isInitialized = ctrl != null && ctrl.value.isInitialized;
    final isPlaying = isInitialized && ctrl.value.isPlaying;
    final durationSec = activeVideo?.durationSec ?? 5.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (activeVideo == null)
          IosSurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const AppIconBadge(
                  icon: CupertinoIcons.film,
                  color: AppColors.warningOrange,
                  boxSize: 44,
                  iconSize: 22,
                  circular: true,
                ),
                const SizedBox(height: 10),
                const Text(
                  'No Local Demo Videos Found',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Connect to your Mac backend or upload an MP4 test video below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _uploadingVideo ? null : _uploadCustomDemoVideo,
                  icon: const AppIcon(
                    CupertinoIcons.cloud_upload_fill,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text('Upload MP4 Demo Video'),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder, width: 0.6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Video viewport
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      if (_demoVideoInitializing)
                        const Center(
                          child: CupertinoActivityIndicator(radius: 14),
                        )
                      else if (isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: ctrl.value.aspectRatio,
                            child: VideoPlayer(ctrl),
                          ),
                        )
                      else
                        _buildDemoVideoFallbackView(activeVideo),

                      // Top HUD: Explicitly labeled DEMO VIDEO (never LIVE)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const IosStatusPill(
                              label: 'DEMO VIDEO',
                              color: AppColors.warningOrange,
                              solid: true,
                            ),
                            IosStatusPill(
                              label:
                                  'T+${_selectedTimestampSec.toStringAsFixed(1)}s / ${durationSec.toStringAsFixed(1)}s',
                              color: AppColors.primaryAccent,
                            ),
                          ],
                        ),
                      ),

                      // Bottom metadata bar
                      Positioned(
                        bottom: 10,
                        left: 12,
                        right: 12,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                activeVideo.locationName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              activeVideo.filename,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Controls + Scrubber + FFmpeg/YOLOv8 Analyze Button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeVideo.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  activeVideo.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IosPressable(
                            onTap: () {
                              if (isInitialized) {
                                setState(() {
                                  ctrl.value.isPlaying
                                      ? ctrl.pause()
                                      : ctrl.play();
                                });
                              } else {
                                _loadedDemoVideoUrl = null;
                                _ensureDemoVideoLoaded(activeVideo);
                              }
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.secondaryBackground,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cardBorder,
                                  width: 0.6,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: AppIcon(
                                isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                size: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IosPressable(
                            onTap: () => _openFullscreenDemoVideo(activeVideo),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.secondaryBackground,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cardBorder,
                                  width: 0.6,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const AppIcon(
                                CupertinoIcons.fullscreen,
                                size: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Frame Timestamp Scrubber
                      Row(
                        children: [
                          const AppIcon(
                            CupertinoIcons.time,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Frame Timestamp: ${_selectedTimestampSec.toStringAsFixed(1)}s',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: AppColors.primaryAccent,
                                inactiveTrackColor: AppColors.secondaryBackground,
                                thumbColor: AppColors.primaryAccent,
                              ),
                              child: Slider(
                                value: _selectedTimestampSec.clamp(
                                  0.0,
                                  durationSec > 0.2 ? durationSec : 5.0,
                                ),
                                min: 0.0,
                                max: durationSec > 0.2 ? durationSec : 5.0,
                                onChanged: (val) {
                                  setState(() => _selectedTimestampSec = val);
                                  if (isInitialized) {
                                    ctrl.seekTo(
                                      Duration(
                                        milliseconds: (val * 1000).round(),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Primary Action: Extract & Analyze Frame via FFmpeg + YOLOv8n
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _extractingFrame
                              ? null
                              : () => _extractAndAnalyzeDemoFrame(activeVideo),
                          icon: _extractingFrame
                              ? const CupertinoActivityIndicator(
                                  radius: 9,
                                  color: Colors.white,
                                )
                              : const AppIcon(
                                  CupertinoIcons.viewfinder,
                                  size: 16,
                                  color: Colors.white,
                                ),
                          label: Text(
                            _extractingFrame
                                ? 'Extracting Frame & Running YOLOv8n…'
                                : 'Extract & Analyze Frame (FFmpeg + YOLOv8n)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Extracted Frame & YOLOv8n Result
        if (_videoFrameResult != null) ...[
          const SizedBox(height: 16),
          IosFadeIn(
            child: _buildExtractedFrameAnalysisCard(
              _videoFrameResult!,
              activeVideo,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Prerecorded Demo Video Library + Upload MP4
        IosSectionHeader(
          title: 'Prerecorded Demo Videos',
          subtitle: 'Local MP4 files served by Mac FastAPI backend',
          icon: CupertinoIcons.film,
          actionLabel: _uploadingVideo ? 'Uploading…' : 'Upload MP4',
          onAction: _uploadingVideo ? null : _uploadCustomDemoVideo,
        ),
        if (videos.isNotEmpty)
          IosSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < videos.length; i++) ...[
                  _buildDemoVideoSelectorRow(
                    videos[i],
                    isSelected: videos[i].id == activeVideo?.id,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDemoVideoId = videos[i].id;
                        _loadedDemoVideoUrl = null;
                        _videoFrameResult = null;
                      });
                      _ensureDemoVideoLoaded(videos[i]);
                    },
                  ),
                  if (i < videos.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 56),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 14),

        // Instructions for adding custom test videos
        const IosSurfaceCard(
          padding: EdgeInsets.all(14),
          color: AppColors.secondaryBackground,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                CupertinoIcons.info_circle_fill,
                size: 16,
                color: AppColors.primaryAccent,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'How to add custom test videos: Tap "Upload MP4" above to upload any MP4/MOV from your iPhone Photos library, or place .mp4 files directly into backend/demo_assets/videos/ on your Mac.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Detection History
        _buildDetectionHistorySection(history),
      ],
    );
  }

  Widget _buildDemoVideoFallbackView(DemoVideoModel video) {
    return Container(
      color: AppColors.secondaryBackground,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(
              icon: CupertinoIcons.film_fill,
              color: AppColors.warningOrange,
              boxSize: 46,
              iconSize: 22,
              circular: true,
            ),
            const SizedBox(height: 10),
            Text(
              video.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _demoVideoError != null
                  ? 'Video stream requires connection to Mac backend. Tap "Extract & Analyze Frame" when connected.'
                  : 'Prerecorded local MP4 demo asset (DEMO VIDEO).',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoVideoSelectorRow(
    DemoVideoModel video, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return IosPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AppIconBadge(
              icon: CupertinoIcons.film_fill,
              color: isSelected
                  ? AppColors.primaryAccent
                  : AppColors.textSecondary,
              boxSize: 36,
              iconSize: 17,
              borderRadius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${video.locationName} · ${video.durationSec.toStringAsFixed(1)}s',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const IosStatusPill(
              label: 'DEMO VIDEO',
              color: AppColors.warningOrange,
            ),
            const SizedBox(width: 6),
            AppIcon(
              isSelected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.chevron_right,
              size: 16,
              color: isSelected
                  ? AppColors.primaryAccent
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedFrameAnalysisCard(
    DetectionResultModel res,
    DemoVideoModel? video,
  ) {
    final frameUrl = (_showVideoBoxes &&
            res.annotatedImageUrl != null &&
            res.annotatedImageUrl!.isNotEmpty)
        ? res.annotatedImageUrl!
        : res.imageUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (frameUrl.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder, width: 0.6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        frameUrl,
                        headers: ngrokHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            'Extracted frame preview unavailable',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IosStatusPill(
                              label:
                                  'EXTRACTED FRAME @ ${(res.frameTimestampSec ?? _selectedTimestampSec).toStringAsFixed(1)}s',
                              color: AppColors.primaryAccent,
                              solid: true,
                            ),
                            const IosStatusPill(
                              label: 'DEMO VIDEO SOURCE',
                              color: AppColors.warningOrange,
                              solid: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Boxes: ${res.boxes.length} · ${res.processingMs} ms',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (res.annotatedImageUrl != null)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => setState(
                            () => _showVideoBoxes = !_showVideoBoxes,
                          ),
                          child: Text(
                            _showVideoBoxes ? 'Raw Frame' : 'Show YOLO Boxes',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _buildDetectionResultCard(res, demoVideo: video),
      ],
    );
  }

  // ===========================================================================
  // MODE B: REAL CAMERAS (Honest Empty State + Add RTSP / HLS Configuration)
  // ===========================================================================
  Widget _buildRealCamerasModeView(
    CameraNode? activeCam,
    List<CameraNode> cameras,
  ) {
    if (cameras.isEmpty || activeCam == null) {
      return IosSurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            const AppIconBadge(
              icon: CupertinoIcons.videocam,
              color: AppColors.primaryAccent,
              boxSize: 52,
              iconSize: 24,
              circular: true,
              showBorder: true,
            ),
            const SizedBox(height: 14),
            const Text(
              'No Real RTSP / HLS Cameras Configured',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.iosDisplayFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No live IP cameras or public RTSP/HLS streams are currently registered. FireWatch AI does not invent camera locations or show fake LIVE badges.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _showAddRealCameraDialog,
                icon: const AppIcon(
                  CupertinoIcons.plus_circle_fill,
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text('Add RTSP / HLS Camera'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(camerasSubTabProvider.notifier).setMode(0);
                },
                icon: const AppIcon(
                  CupertinoIcons.film_fill,
                  size: 15,
                  color: AppColors.primaryAccent,
                ),
                label: const Text('Open DEMO VIDEO Mode'),
              ),
            ),
          ],
        ),
      );
    }

    final ctrl = _realCamController;
    final isInitialized = ctrl != null && ctrl.value.isInitialized;
    final isLiveOk = isInitialized && _realCamError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder, width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.black),
                    if (_realCamInitializing)
                      const Center(
                        child: CupertinoActivityIndicator(radius: 14),
                      )
                    else if (isLiveOk)
                      VideoPlayer(ctrl)
                    else
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            _realCamError != null
                                ? 'Stream unreachable: ${activeCam.url}'
                                : 'Connecting to ${activeCam.url}…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IosStatusPill(
                            label: isLiveOk ? 'RTSP/HLS STREAM' : 'STREAM OFFLINE',
                            color: isLiveOk
                                ? AppColors.statusOk
                                : AppColors.warningOrange,
                          ),
                          IosStatusPill(
                            label:
                                '${activeCam.lat.toStringAsFixed(3)}, ${activeCam.lon.toStringAsFixed(3)}',
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeCam.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activeCam.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IosStatusPill(
                          label: activeCam.status.toUpperCase(),
                          color: activeCam.isOnline
                              ? AppColors.statusOk
                              : (activeCam.isOffline
                                  ? AppColors.dangerRed
                                  : AppColors.warningOrange),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _deleteRealCamera(activeCam),
                          child: const AppIcon(
                            CupertinoIcons.trash,
                            color: AppColors.dangerRed,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    if (activeCam.lastError != null &&
                        activeCam.lastError!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last error: ${activeCam.lastError}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.warningOrange,
                        ),
                      ),
                    ],
                    if (activeCam.lastFrameAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last frame: ${formatRelativeOrShortTime(activeCam.lastFrameAt!)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _checkingStream
                            ? null
                            : () => _checkRealCameraStream(activeCam),
                        icon: _checkingStream
                            ? const CupertinoActivityIndicator(radius: 8)
                            : const AppIcon(
                                CupertinoIcons.antenna_radiowaves_left_right,
                                size: 15,
                                color: AppColors.primaryAccent,
                              ),
                        label: Text(
                          _checkingStream
                              ? 'Probing RTSP/HLS Stream via FFmpeg…'
                              : 'Check Stream Connection',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        IosSectionHeader(
          title: 'Configured Stream Endpoints',
          icon: CupertinoIcons.videocam,
          actionLabel: 'Add Stream',
          onAction: _showAddRealCameraDialog,
        ),
        IosSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < cameras.length; i++) ...[
                IosPressable(
                  onTap: () {
                    ref
                        .read(selectedCameraIdProvider.notifier)
                        .select(cameras[i].id);
                    _loadedRealCamUrl = null;
                    _ensureRealCamLoaded(cameras[i]);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        AppIconBadge(
                          icon: CupertinoIcons.videocam_fill,
                          color: cameras[i].id == activeCam.id
                              ? AppColors.primaryAccent
                              : AppColors.textSecondary,
                          boxSize: 34,
                          iconSize: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cameras[i].name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                cameras[i].url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
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
                ),
                if (i < cameras.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MODE C: AI PHOTO SCANNER + DETECTION HISTORY
  // ===========================================================================
  Widget _buildAiPhotoScannerView(
    SystemStats? stats,
    List<DetectionResultModel> history,
  ) {
    final boxes = _result?.boxes ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder, width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: _selectedBytes == null
                    ? Container(
                        color: AppColors.secondaryBackground,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppIconBadge(
                              icon: CupertinoIcons.viewfinder,
                              color: AppColors.primaryAccent,
                              boxSize: 50,
                              iconSize: 24,
                              circular: true,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'YOLOv8n Optical Fire & Smoke Scanner',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Capture from iPhone Camera, pick from Photos, or load a calibration frame',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_showAnnotated &&
                              _result?.annotatedImageUrl != null &&
                              _result!.annotatedImageUrl!.isNotEmpty)
                            Image.network(
                              _result!.annotatedImageUrl!,
                              headers: ngrokHeaders,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.memory(
                                _selectedBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Image.memory(_selectedBytes!, fit: BoxFit.cover),
                          if (_showAnnotated && boxes.isNotEmpty)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: YoloBoxPainter(boxes),
                              ),
                            ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: IosStatusPill(
                              label: _result != null
                                  ? (_result!.isRealModel
                                      ? 'YOLOv8n REAL MODEL'
                                      : 'DEMO HEURISTIC')
                                  : 'FRAME READY',
                              color: _result != null
                                  ? (_result!.isRealModel
                                      ? AppColors.primaryAccent
                                      : AppColors.warningOrange)
                                  : AppColors.primaryAccent,
                              solid: true,
                            ),
                          ),
                        ],
                      ),
              ),
              if (_selectedBytes != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const AppIcon(
                        CupertinoIcons.photo,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$_selectedFilename (${(_selectedBytes!.length / 1024).toStringAsFixed(1)} KB)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (_result != null)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => setState(
                            () => _showAnnotated = !_showAnnotated,
                          ),
                          child: Text(
                            _showAnnotated ? 'Hide Boxes' : 'Show Boxes',
                            style: const TextStyle(
                              color: AppColors.primaryAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Camera & Photos buttons
        Row(
          children: [
            Expanded(
              child: IosSurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: () => _pickImage(ImageSource.camera),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(
                      CupertinoIcons.camera_fill,
                      size: 16,
                      color: AppColors.primaryAccent,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Camera',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IosSurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onTap: () => _pickImage(ImageSource.gallery),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(
                      CupertinoIcons.photo_fill_on_rectangle_fill,
                      size: 16,
                      color: AppColors.primaryAccent,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Photos',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Calibration Samples
        Row(
          children: [
            Expanded(
              child: IosPressable(
                onTap: _loadingSample ? null : () => _loadTestSample('fire'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(
                        CupertinoIcons.flame_fill,
                        size: 14,
                        color: AppColors.dangerRed,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Sample: Forest Fire',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IosPressable(
                onTap: _loadingSample ? null : () => _loadTestSample('clear'),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon(
                        CupertinoIcons.checkmark_shield_fill,
                        size: 14,
                        color: AppColors.statusOk,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Sample: Clear Forest',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_selectedBytes == null || _analyzing) ? null : _analyzeImage,
            icon: _analyzing
                ? const CupertinoActivityIndicator(
                    radius: 9,
                    color: Colors.white,
                  )
                : const AppIcon(
                    CupertinoIcons.sparkles,
                    size: 16,
                    color: Colors.white,
                  ),
            label: Text(
              _analyzing ? 'Running YOLOv8n Inference…' : 'Run YOLOv8n Analysis',
            ),
          ),
        ),

        if (_result != null) ...[
          const SizedBox(height: 18),
          IosFadeIn(child: _buildDetectionResultCard(_result!)),
        ],

        const SizedBox(height: 22),
        _buildDetectionHistorySection(history),
      ],
    );
  }

  // ===========================================================================
  // SHARED DETECTION RESULT CARD & DETECTION HISTORY
  // ===========================================================================
  Widget _buildDetectionResultCard(
    DetectionResultModel res, {
    DemoVideoModel? demoVideo,
  }) {
    final hasHazard = res.fireDetected || res.smokeDetected;
    final Color statusColor;
    final String statusTitle;
    final IconData statusIcon;

    if (res.classification == 'fire_smoke') {
      statusColor = AppColors.dangerRed;
      statusTitle = 'Fire & Smoke Detected';
      statusIcon = CupertinoIcons.flame_fill;
    } else if (res.classification == 'fire') {
      statusColor = AppColors.dangerRed;
      statusTitle = 'Fire Detected';
      statusIcon = CupertinoIcons.flame_fill;
    } else if (res.classification == 'smoke') {
      statusColor = AppColors.warningOrange;
      statusTitle = 'Smoke Plume Detected';
      statusIcon = CupertinoIcons.smoke_fill;
    } else {
      statusColor = AppColors.statusOk;
      statusTitle = 'Clear · No Fire or Smoke';
      statusIcon = CupertinoIcons.checkmark_shield_fill;
    }

    return IosSurfaceCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      borderColor: statusColor.withValues(alpha: 0.40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IosStatusPill(
                label: res.isRealModel ? 'REAL YOLOv8n' : 'DEMO HEURISTIC',
                color: res.isRealModel
                    ? AppColors.primaryAccent
                    : AppColors.warningOrange,
                pulsingDot: true,
              ),
              Flexible(
                child: Text(
                  '${res.processingMs} ms · ${formatRelativeOrShortTime(res.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppIconBadge(
                icon: statusIcon,
                color: statusColor,
                boxSize: 42,
                iconSize: 20,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontFamily: AppTheme.iosDisplayFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Class: ${res.classification.toUpperCase()} · Model: ${res.modelName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(res.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontFamily: AppTheme.iosDisplayFamily,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: res.confidence.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.secondaryBackground,
              color: statusColor,
            ),
          ),
          if (res.boxes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in res.boxes)
                  IosStatusPill(
                    label:
                        '${b.label.toUpperCase()} ${(b.confidence * 100).toStringAsFixed(1)}%',
                    color: b.label.contains('fire')
                        ? AppColors.dangerRed
                        : AppColors.warningOrange,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            res.disclaimer,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    hasHazard ? AppColors.dangerRed : AppColors.primaryAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: _savingIncident
                  ? null
                  : () => _saveDetectionAsIncident(res, demoVideo: demoVideo),
              icon: _savingIncident
                  ? const CupertinoActivityIndicator(
                      radius: 9,
                      color: Colors.white,
                    )
                  : const AppIcon(
                      CupertinoIcons.exclamationmark_shield_fill,
                      size: 16,
                      color: Colors.white,
                    ),
              label: Text(
                _savingIncident ? 'Creating Incident…' : 'Create Incident',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionHistorySection(List<DetectionResultModel> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IosSectionHeader(
          title: 'Detection History',
          subtitle: 'Recent YOLOv8n frame & image analyses stored in SQLite',
          icon: CupertinoIcons.clock,
        ),
        if (history.isEmpty)
          const IosSurfaceCard(
            padding: EdgeInsets.all(18),
            child: Text(
              'No detections recorded yet. Extract a frame from a DEMO VIDEO or analyze an image above.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          IosSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < history.take(8).length; i++) ...[
                  _buildHistoryRow(history[i]),
                  if (i < history.take(8).length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 68),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryRow(DetectionResultModel item) {
    final isFire = item.fireDetected;
    final isSmoke = item.smokeDetected;
    final color = isFire
        ? AppColors.dangerRed
        : (isSmoke ? AppColors.warningOrange : AppColors.statusOk);
    final thumbUrl = item.annotatedImageUrl ?? item.imageUrl;

    return IosPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _videoFrameResult = item;
          _result = item;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: thumbUrl.isNotEmpty
                    ? Image.network(
                        thumbUrl,
                        headers: ngrokHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.secondaryBackground,
                          child: AppIcon(
                            CupertinoIcons.photo,
                            size: 16,
                            color: color,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.secondaryBackground,
                        child: AppIcon(
                          CupertinoIcons.photo,
                          size: 16,
                          color: color,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.classification.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(item.confidence * 100).toStringAsFixed(1)}% · ${item.boxes.length} box${item.boxes.length == 1 ? '' : 'es'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.isRealModel ? "YOLOv8n" : "Demo"} · ${item.processingMs} ms · ${formatRelativeOrShortTime(item.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IosStatusPill(
              label: item.isRealModel ? 'REAL' : 'DEMO',
              color: item.isRealModel
                  ? AppColors.primaryAccent
                  : AppColors.warningOrange,
            ),
          ],
        ),
      ),
    );
  }
}
