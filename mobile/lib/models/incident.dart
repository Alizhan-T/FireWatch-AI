class Incident {
  final String id;
  final String title;
  final String? description;
  final String source;
  final String? cameraId;
  final String? locationName;
  final double lat;
  final double lon;
  final String severity;
  final String status;
  final String? classification;
  final double? confidence;
  final String detectionMode;
  final String? mediaType;
  final String? mediaUrl;
  final String? mediaNote;
  final bool isDemo;
  final String? detectionId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Incident({
    required this.id,
    required this.title,
    this.description,
    required this.source,
    this.cameraId,
    this.locationName,
    required this.lat,
    required this.lon,
    required this.severity,
    required this.status,
    this.classification,
    this.confidence,
    required this.detectionMode,
    this.mediaType,
    this.mediaUrl,
    this.mediaNote,
    required this.isDemo,
    this.detectionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Incident.fromMap(Map<String, dynamic> m, {String baseUrl = ''}) {
    final rawMedia = (m['media_url'] ?? m['video_url'])?.toString();
    String? resolvedMedia;
    if (rawMedia != null && rawMedia.isNotEmpty) {
      if (rawMedia.startsWith('http://') || rawMedia.startsWith('https://')) {
        resolvedMedia = rawMedia;
      } else if (baseUrl.isNotEmpty) {
        final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
        final cleanPath = rawMedia.startsWith('/') ? rawMedia : '/$rawMedia';
        resolvedMedia = '$cleanBase$cleanPath';
      } else {
        resolvedMedia = rawMedia;
      }
    }

    final createdStr =
        (m['created_at'] ?? m['detected_at'] ?? '').toString();
    final updatedStr = (m['updated_at'] ?? createdStr).toString();
    final created = DateTime.tryParse(createdStr)?.toLocal() ?? DateTime.now();
    final updated = DateTime.tryParse(updatedStr)?.toLocal() ?? created;

    final rawConf = m['confidence'];
    final double? conf = rawConf == null
        ? null
        : (rawConf is num ? rawConf.toDouble() : double.tryParse('$rawConf'));

    final rawDemo = m['is_demo'];
    final isDemo = rawDemo == true || rawDemo == 1 || rawDemo == '1' || rawDemo == 'true';

    final camName = m['location_name']?.toString() ?? m['camera_name']?.toString();
    final title = (m['title']?.toString().isNotEmpty ?? false)
        ? m['title'].toString()
        : (camName ?? 'Fire Incident');

    return Incident(
      id: (m['id'] ?? m['incident_id'] ?? '').toString(),
      title: title,
      description: m['description']?.toString(),
      source: (m['source'] ?? (isDemo ? 'simulation' : 'manual')).toString(),
      cameraId: m['camera_id']?.toString(),
      locationName: camName,
      lat: double.tryParse('${m['lat']}') ?? 0.0,
      lon: double.tryParse('${m['lon']}') ?? 0.0,
      severity: (m['severity'] ?? m['threat_level'] ?? 'high')
          .toString()
          .toLowerCase(),
      status: (m['status'] ?? 'new').toString().toLowerCase(),
      classification: m['classification']?.toString(),
      confidence: conf,
      detectionMode:
          (m['detection_mode'] ?? (isDemo ? 'simulated' : 'manual')).toString(),
      mediaType: m['media_type']?.toString() ??
          (resolvedMedia != null && resolvedMedia.endsWith('.mp4')
              ? 'video'
              : (resolvedMedia != null ? 'image' : null)),
      mediaUrl: resolvedMedia,
      mediaNote: m['media_note']?.toString(),
      isDemo: isDemo,
      detectionId: m['detection_id']?.toString(),
      createdAt: created,
      updatedAt: updated,
    );
  }

  Incident copyWith({
    String? status,
    DateTime? updatedAt,
  }) {
    return Incident(
      id: id,
      title: title,
      description: description,
      source: source,
      cameraId: cameraId,
      locationName: locationName,
      lat: lat,
      lon: lon,
      severity: severity,
      status: status ?? this.status,
      classification: classification,
      confidence: confidence,
      detectionMode: detectionMode,
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      mediaNote: mediaNote,
      isDemo: isDemo,
      detectionId: detectionId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isValid => id.isNotEmpty;
  bool get isActive => status == 'new' || status == 'acknowledged';
}

class CameraNode {
  final String id;
  final String name;
  final String url;
  final double lat;
  final double lon;
  final String status; // 'unchecked' | 'online' | 'offline'
  final DateTime? lastCheckedAt;
  final DateTime? lastFrameAt;
  final String? lastError;
  final String? snapshotUrl;

  const CameraNode({
    required this.id,
    required this.name,
    required this.url,
    required this.lat,
    required this.lon,
    this.status = 'unchecked',
    this.lastCheckedAt,
    this.lastFrameAt,
    this.lastError,
    this.snapshotUrl,
  });

  bool get isOnline => status == 'online';
  bool get isOffline => status == 'offline';

  factory CameraNode.fromMap(Map<String, dynamic> m, {String baseUrl = ''}) {
    final rawSnap = m['snapshot_url']?.toString();
    String? resolvedSnap;
    if (rawSnap != null && rawSnap.isNotEmpty) {
      if (rawSnap.startsWith('http://') || rawSnap.startsWith('https://')) {
        resolvedSnap = rawSnap;
      } else if (baseUrl.isNotEmpty) {
        final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
        final cleanPath = rawSnap.startsWith('/') ? rawSnap : '/$rawSnap';
        resolvedSnap = '$cleanBase$cleanPath';
      } else {
        resolvedSnap = rawSnap;
      }
    }
    return CameraNode(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? 'Camera'}',
      url: '${m['url'] ?? ''}',
      lat: double.tryParse('${m['lat']}') ?? 0.0,
      lon: double.tryParse('${m['lon']}') ?? 0.0,
      status: (m['status'] ?? 'unchecked').toString().toLowerCase(),
      lastCheckedAt: m['last_checked_at'] != null
          ? DateTime.tryParse('${m['last_checked_at']}')?.toLocal()
          : null,
      lastFrameAt: m['last_frame_at'] != null
          ? DateTime.tryParse('${m['last_frame_at']}')?.toLocal()
          : null,
      lastError: m['last_error']?.toString(),
      snapshotUrl: resolvedSnap,
    );
  }
}

class RiskZone {
  final double lat;
  final double lon;
  final String severity;
  final double radiusM;
  final int incidentCount;
  final List<String> incidentIds;
  final bool isDemo;

  const RiskZone({
    required this.lat,
    required this.lon,
    required this.severity,
    required this.radiusM,
    required this.incidentCount,
    required this.incidentIds,
    this.isDemo = false,
  });

  factory RiskZone.fromMap(Map<String, dynamic> m) => RiskZone(
        lat: double.tryParse('${m['lat']}') ?? 0.0,
        lon: double.tryParse('${m['lon']}') ?? 0.0,
        severity: (m['severity'] ?? 'high').toString().toLowerCase(),
        radiusM: double.tryParse('${m['radius_m']}') ?? 2000.0,
        incidentCount: int.tryParse('${m['incident_count']}') ?? 1,
        incidentIds: (m['incident_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        isDemo: m['is_demo'] == true,
      );
}

class DemoVideoModel {
  final String id;
  final String title;
  final String filename;
  final String videoUrl;
  final double durationSec;
  final String description;
  final String locationName;
  final double lat;
  final double lon;
  final bool isDemo;
  final String badge;

  const DemoVideoModel({
    required this.id,
    required this.title,
    required this.filename,
    required this.videoUrl,
    required this.durationSec,
    required this.description,
    required this.locationName,
    required this.lat,
    required this.lon,
    this.isDemo = true,
    this.badge = 'DEMO VIDEO',
  });

  factory DemoVideoModel.fromMap(
    Map<String, dynamic> m, {
    String baseUrl = '',
  }) {
    final rawUrl = (m['video_url'] ?? '').toString();
    String resolvedUrl = rawUrl;
    if (rawUrl.isNotEmpty &&
        !rawUrl.startsWith('http://') &&
        !rawUrl.startsWith('https://') &&
        baseUrl.isNotEmpty) {
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final cleanPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
      resolvedUrl = '$cleanBase$cleanPath';
    }
    return DemoVideoModel(
      id: '${m['id'] ?? ''}',
      title: '${m['title'] ?? 'DEMO VIDEO'}',
      filename: '${m['filename'] ?? ''}',
      videoUrl: resolvedUrl,
      durationSec: double.tryParse('${m['duration_sec']}') ?? 5.0,
      description: '${m['description'] ?? ''}',
      locationName: '${m['location_name'] ?? 'Local Demo Video'}',
      lat: double.tryParse('${m['lat']}') ?? 43.2389,
      lon: double.tryParse('${m['lon']}') ?? 76.8897,
      isDemo: m['is_demo'] != false,
      badge: '${m['badge'] ?? 'DEMO VIDEO'}',
    );
  }
}

class DetectionBox {
  final String label;
  final double confidence;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const DetectionBox({
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory DetectionBox.fromMap(Map<String, dynamic> m) => DetectionBox(
        label: '${m['label'] ?? 'fire'}',
        confidence: double.tryParse('${m['confidence']}') ?? 0.0,
        x1: double.tryParse('${m['x1']}') ?? 0.0,
        y1: double.tryParse('${m['y1']}') ?? 0.0,
        x2: double.tryParse('${m['x2']}') ?? 0.0,
        y2: double.tryParse('${m['y2']}') ?? 0.0,
      );
}

class DetectionResultModel {
  final String id;
  final String status;
  final String mode;
  final String provider;
  final String modelName;
  final String classification;
  final bool fireDetected;
  final bool smokeDetected;
  final double confidence;
  final List<DetectionBox> boxes;
  final int processingMs;
  final String imageUrl;
  final String? annotatedImageUrl;
  final String disclaimer;
  final String? incidentId;
  final String? sourceVideoId;
  final double? frameTimestampSec;
  final DateTime createdAt;

  const DetectionResultModel({
    required this.id,
    required this.status,
    required this.mode,
    required this.provider,
    required this.modelName,
    required this.classification,
    required this.fireDetected,
    required this.smokeDetected,
    required this.confidence,
    required this.boxes,
    required this.processingMs,
    required this.imageUrl,
    this.annotatedImageUrl,
    required this.disclaimer,
    this.incidentId,
    this.sourceVideoId,
    this.frameTimestampSec,
    required this.createdAt,
  });

  bool get isRealModel => mode == 'real_model';

  factory DetectionResultModel.fromMap(
    Map<String, dynamic> m, {
    String baseUrl = '',
  }) {
    String resolveUrl(String? raw) {
      if (raw == null || raw.isEmpty) return '';
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
      if (baseUrl.isEmpty) return raw;
      final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final cleanPath = raw.startsWith('/') ? raw : '/$raw';
      return '$cleanBase$cleanPath';
    }

    final rawAnn = m['annotated_image_url']?.toString();
    final rawFrameTs = m['frame_timestamp_sec'];
    return DetectionResultModel(
      id: '${m['id'] ?? ''}',
      status: '${m['status'] ?? 'completed'}',
      mode: '${m['mode'] ?? 'demo_heuristic'}',
      provider: '${m['provider'] ?? ''}',
      modelName: '${m['model_name'] ?? ''}',
      classification: '${m['classification'] ?? 'none'}',
      fireDetected: m['fire_detected'] == true,
      smokeDetected: m['smoke_detected'] == true,
      confidence: double.tryParse('${m['confidence']}') ?? 0.0,
      boxes: (m['boxes'] as List?)
              ?.map((e) => DetectionBox.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      processingMs: int.tryParse('${m['processing_ms']}') ?? 0,
      imageUrl: resolveUrl(m['image_url']?.toString()),
      annotatedImageUrl:
          (rawAnn != null && rawAnn.isNotEmpty) ? resolveUrl(rawAnn) : null,
      disclaimer: '${m['disclaimer'] ?? ''}',
      incidentId: m['incident_id']?.toString(),
      sourceVideoId: m['source_video_id']?.toString(),
      frameTimestampSec:
          rawFrameTs == null ? null : double.tryParse('$rawFrameTs'),
      createdAt:
          DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

class LatestDetectionSummary {
  final String id;
  final String classification;
  final double confidence;
  final String mode;
  final String? sourceVideoId;
  final double? frameTimestampSec;
  final DateTime createdAt;

  const LatestDetectionSummary({
    required this.id,
    required this.classification,
    required this.confidence,
    required this.mode,
    this.sourceVideoId,
    this.frameTimestampSec,
    required this.createdAt,
  });

  factory LatestDetectionSummary.fromMap(Map<String, dynamic> m) =>
      LatestDetectionSummary(
        id: '${m['id'] ?? ''}',
        classification: '${m['classification'] ?? 'none'}',
        confidence: double.tryParse('${m['confidence']}') ?? 0.0,
        mode: '${m['mode'] ?? 'real_model'}',
        sourceVideoId: m['source_video_id']?.toString(),
        frameTimestampSec: m['frame_timestamp_sec'] != null
            ? double.tryParse('${m['frame_timestamp_sec']}')
            : null,
        createdAt:
            DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}

class SystemStats {
  final int totalIncidents;
  final int activeIncidents;
  final Map<String, int> activeBySeverity;
  final int last24hIncidents;
  final int demoIncidents;
  final int totalDetections;
  final int fireDetections;
  final int smokeDetections;
  final int clearDetections;
  final Map<String, int> detectionsByClassification;
  final Map<String, int> detectionsByMode;
  final int? avgProcessingMs;
  final int highRiskZones;
  final int camerasConfigured;
  final int camerasOnline;
  final int demoVideosAvailable;
  final int devicesRegistered;
  final String detectorMode;
  final String detectorProvider;
  final String detectorModelName;
  final String detectorDisclaimer;
  final String? detectorFallbackReason;
  final String firebaseStatus;
  final LatestDetectionSummary? latestDetection;
  final bool isOfflineDemo;

  const SystemStats({
    required this.totalIncidents,
    required this.activeIncidents,
    required this.activeBySeverity,
    required this.last24hIncidents,
    required this.demoIncidents,
    required this.totalDetections,
    this.fireDetections = 0,
    this.smokeDetections = 0,
    this.clearDetections = 0,
    required this.detectionsByClassification,
    required this.detectionsByMode,
    this.avgProcessingMs,
    required this.highRiskZones,
    required this.camerasConfigured,
    this.camerasOnline = 0,
    this.demoVideosAvailable = 2,
    required this.devicesRegistered,
    required this.detectorMode,
    required this.detectorProvider,
    required this.detectorModelName,
    required this.detectorDisclaimer,
    this.detectorFallbackReason,
    required this.firebaseStatus,
    this.latestDetection,
    this.isOfflineDemo = false,
  });

  bool get isRealModel => detectorMode == 'real_model';

  factory SystemStats.fromMap(Map<String, dynamic> m,
      {bool isOfflineDemo = false}) {
    final inc = (m['incidents'] as Map?)?.cast<String, dynamic>() ?? const {};
    final det = (m['detections'] as Map?)?.cast<String, dynamic>() ?? const {};
    final detector =
        (m['detector'] as Map?)?.cast<String, dynamic>() ?? const {};
    final latestRaw = m['latest_detection'];

    Map<String, int> toIntMap(dynamic raw) {
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry('$k', int.tryParse('$v') ?? 0));
    }

    final byCls = toIntMap(det['by_classification']);
    final fireCount = int.tryParse('${m['fire_detections']}') ??
        ((byCls['fire'] ?? 0) + (byCls['fire_smoke'] ?? 0));
    final smokeCount = int.tryParse('${m['smoke_detections']}') ??
        ((byCls['smoke'] ?? 0) + (byCls['fire_smoke'] ?? 0));
    final clearCount =
        int.tryParse('${m['clear_detections']}') ?? (byCls['none'] ?? 0);

    return SystemStats(
      totalIncidents: int.tryParse('${inc['total']}') ?? 0,
      activeIncidents: int.tryParse('${inc['active']}') ?? 0,
      activeBySeverity: toIntMap(inc['active_by_severity']),
      last24hIncidents: int.tryParse('${inc['last_24h']}') ?? 0,
      demoIncidents: int.tryParse('${inc['demo']}') ?? 0,
      totalDetections: int.tryParse('${det['total']}') ?? 0,
      fireDetections: fireCount,
      smokeDetections: smokeCount,
      clearDetections: clearCount,
      detectionsByClassification: byCls,
      detectionsByMode: toIntMap(det['by_mode']),
      avgProcessingMs: det['avg_processing_ms'] == null
          ? null
          : int.tryParse('${det['avg_processing_ms']}'),
      highRiskZones: int.tryParse('${m['high_risk_zones']}') ?? 0,
      camerasConfigured: int.tryParse('${m['cameras_configured']}') ?? 0,
      camerasOnline: int.tryParse('${m['cameras_online']}') ?? 0,
      demoVideosAvailable: int.tryParse('${m['demo_videos_available']}') ?? 2,
      devicesRegistered: int.tryParse('${m['devices_registered']}') ?? 0,
      detectorMode: '${detector['mode'] ?? 'demo_heuristic'}',
      detectorProvider: '${detector['provider'] ?? 'unknown'}',
      detectorModelName: '${detector['model_name'] ?? 'Unknown'}',
      detectorDisclaimer: '${detector['disclaimer'] ?? ''}',
      detectorFallbackReason: detector['fallback_reason']?.toString(),
      firebaseStatus: '${m['firebase'] ?? 'not_configured'}',
      latestDetection: latestRaw is Map<String, dynamic>
          ? LatestDetectionSummary.fromMap(latestRaw)
          : null,
      isOfflineDemo: isOfflineDemo,
    );
  }
}

class UserProfile {
  final String name;
  final String role;
  final String unit;

  const UserProfile({
    required this.name,
    required this.role,
    required this.unit,
  });

  UserProfile copyWith({String? name, String? role, String? unit}) =>
      UserProfile(
        name: name ?? this.name,
        role: role ?? this.role,
        unit: unit ?? this.unit,
      );
}
