import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/incident.dart';

/// Заголовок для обхода HTML-заглушки бесплатного ngrok при удалённом доступе.
const ngrokHeaders = {'ngrok-skip-browser-warning': 'true'};

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() =>
      statusCode != null ? 'HTTP $statusCode: $message' : message;
}

class EndpointProbeResult {
  const EndpointProbeResult({
    required this.endpoint,
    required this.ok,
    required this.latencyMs,
    this.statusCode,
    required this.summary,
    this.error,
  });

  final String endpoint;
  final bool ok;
  final int? statusCode;
  final int latencyMs;
  final String summary;
  final String? error;
}

class BackendDiagnosticsReport {
  const BackendDiagnosticsReport({
    required this.serverUrl,
    required this.checkedAt,
    required this.isConnected,
    required this.offlineDemoMode,
    required this.healthProbe,
    required this.camerasProbe,
    required this.incidentsProbe,
    required this.statsProbe,
    required this.responseTimeMs,
    this.detectorMode,
    this.detectorModelName,
    this.databaseOk,
    this.ffmpegAvailable,
    this.yoloLoaded,
    this.envMode,
    this.lanUrl,
    this.demoVideosAvailable,
    this.lastError,
  });

  final String serverUrl;
  final DateTime checkedAt;
  final bool isConnected;
  final bool offlineDemoMode;
  final EndpointProbeResult healthProbe;
  final EndpointProbeResult camerasProbe;
  final EndpointProbeResult incidentsProbe;
  final EndpointProbeResult statsProbe;
  final int responseTimeMs;
  final String? detectorMode;
  final String? detectorModelName;
  final bool? databaseOk;
  final bool? ffmpegAvailable;
  final bool? yoloLoaded;
  final String? envMode;
  final String? lanUrl;
  final int? demoVideosAvailable;
  final String? lastError;
}

String formatHumanReadableNetworkError(Object error, String url) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (url.contains('127.0.0.1') || url.contains('localhost')) {
    return 'Loopback address ($url) refers to the iPhone itself. Select Mac Wi-Fi IP (http://192.168.1.101:8000) to connect from a physical iPhone.';
  }
  if (error is TimeoutException || lower.contains('timeoutexception')) {
    return 'Connection timed out reaching $url. Verify that your iPhone and Mac are on the same Wi-Fi network and Uvicorn is running with --host 0.0.0.0 --port 8000.';
  }
  if (lower.contains('connection refused')) {
    return 'Connection refused by $url. Ensure FastAPI backend is running on port 8000 (--host 0.0.0.0).';
  }
  if (lower.contains('network is unreachable') ||
      lower.contains('no route to host') ||
      lower.contains('host lookup') ||
      lower.contains('socketexception')) {
    return 'Cannot reach host $url over local network. Check that Local Network permission is enabled for FireWatch AI in iOS Settings and both devices share the same Wi-Fi.';
  }
  return raw;
}

/// Локальное DEMO-хранилище в памяти на случай, если пользователь явно включил
/// автономный демо-режим без запущенного бэкенда. Все данные явно помечены как DEMO.
class LocalDemoStore {
  LocalDemoStore._();
  static final instance = LocalDemoStore._();

  final List<CameraNode> cameras = const [];

  final List<DemoVideoModel> demoVideos = const [
    DemoVideoModel(
      id: 'demo_wildfire_active',
      title: 'Burabay Sector 4 — Wildfire Outbreak (DEMO VIDEO)',
      filename: 'demo_wildfire_active.mp4',
      videoUrl: '',
      durationSec: 5.0,
      description:
          'Локальная предзаписанная видеозапись очага возгорания для демонстрации FFmpeg + YOLOv8n.',
      locationName: 'Burabay National Park, Sector 4 (DEMO)',
      lat: 53.0833,
      lon: 70.3000,
    ),
    DemoVideoModel(
      id: 'demo_forest_clear',
      title: 'Ile-Alatau Gorge — Clear Forest Patrol (DEMO VIDEO)',
      filename: 'demo_forest_clear.mp4',
      videoUrl: '',
      durationSec: 5.0,
      description:
          'Локальная предзаписанная видеозапись чистого лесного массива без огня и дыма.',
      locationName: 'Ile-Alatau Sector 7 (DEMO)',
      lat: 43.0500,
      lon: 76.9800,
    ),
  ];

  final List<Incident> _incidents = [];
  int _detectionsCount = 0;
  int _seq = 1;

  List<Incident> listIncidents({
    String? severity,
    String? status,
    String? type,
    String? query,
  }) {
    final qLower = query?.trim().toLowerCase() ?? '';
    return _incidents.where((i) {
      if (severity != null && i.severity != severity) return false;
      if (status != null && i.status != status) return false;
      if (type != null && type.isNotEmpty) {
        final cls = (i.classification ?? '').toLowerCase();
        if (type == 'fire' && cls != 'fire' && cls != 'fire_smoke') {
          return false;
        }
        if (type == 'smoke' && cls != 'smoke' && cls != 'fire_smoke') {
          return false;
        }
      }
      if (qLower.isNotEmpty) {
        final hay =
            '${i.title} ${i.locationName ?? ''} ${i.id} ${i.description ?? ''}'
                .toLowerCase();
        if (!hay.contains(qLower)) return false;
      }
      return true;
    }).toList();
  }

  void deleteIncident(String id) {
    _incidents.removeWhere((i) => i.id == id);
  }

  Incident? getIncident(String id) {
    for (final i in _incidents) {
      if (i.id == id) return i;
    }
    return null;
  }

  Incident simulateFire({String? cameraId, String severity = 'high'}) {
    final cam = cameras.isNotEmpty
        ? cameras.firstWhere(
            (c) => c.id == cameraId,
            orElse: () => cameras.first,
          )
        : const CameraNode(
            id: 'demo_sector',
            name: 'Зона мониторинга (DEMO)',
            url: '',
            lat: 43.2389,
            lon: 76.8897,
          );
    final now = DateTime.now();
    final offset = (_seq % 5) * 0.006;
    final inc = Incident(
      id: 'demo_inc_${now.millisecondsSinceEpoch}_${_seq++}',
      title: 'Симуляция (Offline Demo): ${cam.name}',
      description:
          'Симулированный инцидент, созданный в автономном DEMO-режиме приложения без подключения к бэкенду.',
      source: 'simulation',
      cameraId: cam.id,
      locationName: cam.name,
      lat: cam.lat + offset,
      lon: cam.lon + offset,
      severity: severity,
      status: 'new',
      classification: 'fire',
      confidence: null,
      detectionMode: 'simulated',
      mediaType: null,
      mediaUrl: null,
      mediaNote:
          'Автономный DEMO-режим (сервер не задействован). Запустите FastAPI бэкенд для сохранения в SQLite и генерации медиа.',
      isDemo: true,
      createdAt: now,
      updatedAt: now,
    );
    _incidents.insert(0, inc);
    return inc;
  }

  Incident createManualIncident({
    required String title,
    required double lat,
    required double lon,
    required String severity,
    String? locationName,
    String? description,
    String? classification,
    double? confidence,
    String? detectionId,
  }) {
    final now = DateTime.now();
    final inc = Incident(
      id: 'demo_manual_${now.millisecondsSinceEpoch}_${_seq++}',
      title: title,
      description: description,
      source: detectionId != null ? 'detection' : 'manual',
      locationName: locationName ?? 'Локальная запись (Offline Demo)',
      lat: lat,
      lon: lon,
      severity: severity,
      status: 'new',
      classification: classification,
      confidence: confidence,
      detectionMode: detectionId != null ? 'demo_heuristic' : 'manual',
      isDemo: true,
      detectionId: detectionId,
      mediaNote: 'Создано в автономном DEMO-режиме без бэкенда.',
      createdAt: now,
      updatedAt: now,
    );
    _incidents.insert(0, inc);
    return inc;
  }

  Incident updateStatus(String id, String status) {
    final idx = _incidents.indexWhere((i) => i.id == id);
    if (idx == -1) throw const ApiException('Инцидент не найден', 404);
    final updated = _incidents[idx].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    _incidents[idx] = updated;
    return updated;
  }

  List<RiskZone> riskZones() {
    final activeHigh = _incidents.where((i) =>
        i.isActive && (i.severity == 'high' || i.severity == 'critical'));
    return activeHigh
        .map((i) => RiskZone(
              lat: i.lat,
              lon: i.lon,
              severity: i.severity,
              radiusM: i.severity == 'critical' ? 3500 : 2000,
              incidentCount: 1,
              incidentIds: [i.id],
            ))
        .toList();
  }

  SystemStats stats() {
    final active = _incidents.where((i) => i.isActive).toList();
    final bySev = <String, int>{};
    for (final i in active) {
      bySev[i.severity] = (bySev[i.severity] ?? 0) + 1;
    }
    return SystemStats(
      totalIncidents: _incidents.length,
      activeIncidents: active.length,
      activeBySeverity: bySev,
      last24hIncidents: _incidents.length,
      demoIncidents: _incidents.length,
      totalDetections: _detectionsCount,
      detectionsByClassification:
          _detectionsCount > 0 ? {'fire': _detectionsCount} : const {},
      detectionsByMode:
          _detectionsCount > 0 ? {'demo_heuristic': _detectionsCount} : const {},
      avgProcessingMs: _detectionsCount > 0 ? 18 : null,
      highRiskZones: riskZones().length,
      camerasConfigured: cameras.length,
      devicesRegistered: 0,
      detectorMode: 'demo_heuristic',
      detectorProvider: 'offline-local-demo',
      detectorModelName: 'Offline Demo Heuristic (Backend Disconnected)',
      detectorDisclaimer:
          'OFFLINE DEMO MODE: приложение работает автономно без подключения к FastAPI. Для реальной нейросети YOLOv8n подключитесь к бэкенду (http://192.168.1.101:8000).',
      firebaseStatus: 'not_configured',
      isOfflineDemo: true,
    );
  }

  DetectionResultModel detectOffline(Uint8List bytes) {
    _detectionsCount++;
    var warmSum = 0;
    final step = (bytes.length / 500).ceil().clamp(1, 1000);
    var samples = 0;
    for (var i = 0; i < bytes.length; i += step) {
      warmSum += bytes[i];
      samples++;
    }
    final ratio = samples > 0 ? (warmSum / (samples * 255.0)) : 0.0;
    final score = double.parse(ratio.clamp(0.15, 0.85).toStringAsFixed(3));
    return DetectionResultModel(
      id: 'demo_det_${DateTime.now().millisecondsSinceEpoch}',
      status: 'completed',
      mode: 'demo_heuristic',
      provider: 'offline-local-demo',
      modelName: 'Offline Demo Mode (Not a trained model)',
      classification: 'fire',
      fireDetected: true,
      smokeDetected: false,
      confidence: score,
      boxes: const [],
      processingMs: 12,
      imageUrl: '',
      annotatedImageUrl: null,
      disclaimer:
          'DEMO / SIMULATED DETECTION (Offline): бэкенд не подключён. Для реального анализа нейросетью YOLOv8n запустите бэкенд и выключите автономный режим.',
      createdAt: DateTime.now(),
    );
  }
}

class ApiService {
  ApiService(this.baseUrl, {this.offlineDemoMode = false});

  final String baseUrl;
  final bool offlineDemoMode;

  String get cleanBaseUrl => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Uri _u(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$cleanBaseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Map<String, dynamic> _decodeObject(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      try {
        final j = jsonDecode(text);
        if (j is Map && j['detail'] != null) {
          throw ApiException('${j['detail']}', r.statusCode);
        }
      } catch (e) {
        if (e is ApiException) rethrow;
      }
      throw ApiException(text.isEmpty ? 'Ошибка запроса' : text, r.statusCode);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  List<dynamic> _decodeList(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(text.isEmpty ? 'Ошибка запроса' : text, r.statusCode);
    }
    return jsonDecode(text) as List<dynamic>;
  }

  /// Real network probe to GET /health (ignores offlineDemoMode so it never fakes Connected).
  Future<({Map<String, dynamic> data, int latencyMs})> probeLiveHealth({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final sw = Stopwatch()..start();
    final r = await http
        .get(_u('/health'), headers: ngrokHeaders)
        .timeout(timeout);
    sw.stop();
    final map = _decodeObject(r);
    return (data: map, latencyMs: sw.elapsedMilliseconds);
  }

  /// Comprehensive live diagnostics across /health, /cameras, /incidents, and /stats.
  Future<BackendDiagnosticsReport> runDiagnostics({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final totalSw = Stopwatch()..start();
    String? lastError;
    String? detectorMode;
    String? detectorModelName;
    bool? databaseOk;
    bool? ffmpegAvailable;
    bool? yoloLoaded;
    String? envMode;
    String? lanUrl;
    int? demoVideosAvailable;

    // 1. Probe /health
    EndpointProbeResult healthProbe;
    final swHealth = Stopwatch()..start();
    try {
      final r = await http
          .get(_u('/health'), headers: ngrokHeaders)
          .timeout(timeout);
      swHealth.stop();
      final body = _decodeObject(r);
      final det = (body['detector'] as Map?)?.cast<String, dynamic>();
      detectorMode = det?['mode']?.toString();
      detectorModelName = det?['model_name']?.toString();
      databaseOk = body['database'] == true;
      ffmpegAvailable = body['ffmpeg'] == true;
      yoloLoaded = body['yolo_loaded'] == true || detectorMode == 'real_model';
      envMode = body['env_mode']?.toString();
      lanUrl = body['lan_url']?.toString();
      demoVideosAvailable = int.tryParse('${body['demo_videos_available']}');
      healthProbe = EndpointProbeResult(
        endpoint: 'GET /health',
        ok: body['status'] == 'ok',
        statusCode: r.statusCode,
        latencyMs: swHealth.elapsedMilliseconds,
        summary:
            'status=${body['status']}, db=${databaseOk == true ? "ok" : "err"}, model=${detectorMode ?? "unknown"}',
      );
    } catch (e) {
      swHealth.stop();
      final msg = formatHumanReadableNetworkError(e, cleanBaseUrl);
      lastError = msg;
      healthProbe = EndpointProbeResult(
        endpoint: 'GET /health',
        ok: false,
        statusCode: e is ApiException ? e.statusCode : null,
        latencyMs: swHealth.elapsedMilliseconds,
        summary: 'Unreachable',
        error: msg,
      );
    }

    // 2. Probe /cameras
    EndpointProbeResult camerasProbe;
    final swCam = Stopwatch()..start();
    try {
      final r = await http
          .get(_u('/cameras'), headers: ngrokHeaders)
          .timeout(timeout);
      swCam.stop();
      final list = _decodeList(r);
      camerasProbe = EndpointProbeResult(
        endpoint: 'GET /cameras',
        ok: true,
        statusCode: r.statusCode,
        latencyMs: swCam.elapsedMilliseconds,
        summary: '${list.length} cameras configured',
      );
    } catch (e) {
      swCam.stop();
      final msg = formatHumanReadableNetworkError(e, cleanBaseUrl);
      lastError ??= msg;
      camerasProbe = EndpointProbeResult(
        endpoint: 'GET /cameras',
        ok: false,
        statusCode: e is ApiException ? e.statusCode : null,
        latencyMs: swCam.elapsedMilliseconds,
        summary: 'Failed',
        error: msg,
      );
    }

    // 3. Probe /incidents
    EndpointProbeResult incidentsProbe;
    final swInc = Stopwatch()..start();
    try {
      final r = await http
          .get(_u('/incidents'), headers: ngrokHeaders)
          .timeout(timeout);
      swInc.stop();
      final list = _decodeList(r);
      incidentsProbe = EndpointProbeResult(
        endpoint: 'GET /incidents',
        ok: true,
        statusCode: r.statusCode,
        latencyMs: swInc.elapsedMilliseconds,
        summary: '${list.length} incidents in SQLite',
      );
    } catch (e) {
      swInc.stop();
      final msg = formatHumanReadableNetworkError(e, cleanBaseUrl);
      lastError ??= msg;
      incidentsProbe = EndpointProbeResult(
        endpoint: 'GET /incidents',
        ok: false,
        statusCode: e is ApiException ? e.statusCode : null,
        latencyMs: swInc.elapsedMilliseconds,
        summary: 'Failed',
        error: msg,
      );
    }

    // 4. Probe /stats
    EndpointProbeResult statsProbe;
    final swStats = Stopwatch()..start();
    try {
      final r = await http
          .get(_u('/stats'), headers: ngrokHeaders)
          .timeout(timeout);
      swStats.stop();
      final map = _decodeObject(r);
      final s = SystemStats.fromMap(map);
      detectorMode ??= s.detectorMode;
      detectorModelName ??= s.detectorModelName;
      statsProbe = EndpointProbeResult(
        endpoint: 'GET /stats',
        ok: true,
        statusCode: r.statusCode,
        latencyMs: swStats.elapsedMilliseconds,
        summary:
            '${s.activeIncidents} active, ${s.totalDetections} detections',
      );
    } catch (e) {
      swStats.stop();
      final msg = formatHumanReadableNetworkError(e, cleanBaseUrl);
      lastError ??= msg;
      statsProbe = EndpointProbeResult(
        endpoint: 'GET /stats',
        ok: false,
        statusCode: e is ApiException ? e.statusCode : null,
        latencyMs: swStats.elapsedMilliseconds,
        summary: 'Failed',
        error: msg,
      );
    }

    totalSw.stop();
    final isConnected =
        healthProbe.ok && camerasProbe.ok && incidentsProbe.ok;

    return BackendDiagnosticsReport(
      serverUrl: cleanBaseUrl,
      checkedAt: DateTime.now(),
      isConnected: isConnected,
      offlineDemoMode: offlineDemoMode,
      healthProbe: healthProbe,
      camerasProbe: camerasProbe,
      incidentsProbe: incidentsProbe,
      statsProbe: statsProbe,
      responseTimeMs: healthProbe.ok
          ? healthProbe.latencyMs
          : totalSw.elapsedMilliseconds,
      detectorMode: detectorMode,
      detectorModelName: detectorModelName,
      databaseOk: databaseOk,
      ffmpegAvailable: ffmpegAvailable,
      yoloLoaded: yoloLoaded,
      envMode: envMode,
      lanUrl: lanUrl,
      demoVideosAvailable: demoVideosAvailable,
      lastError: lastError,
    );
  }

  Future<Map<String, dynamic>> health() async {
    if (offlineDemoMode) {
      return {
        'status': 'offline_demo',
        'database': false,
        'detector': {
          'mode': 'demo_heuristic',
          'model_name': 'Offline Demo Mode',
        },
        'firebase': 'not_configured',
      };
    }
    final r = await http
        .get(_u('/health'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return _decodeObject(r);
  }

  Future<SystemStats> stats() async {
    if (offlineDemoMode) return LocalDemoStore.instance.stats();
    final r = await http
        .get(_u('/stats'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return SystemStats.fromMap(_decodeObject(r));
  }

  Future<List<CameraNode>> cameras() async {
    if (offlineDemoMode) return LocalDemoStore.instance.cameras;
    final r = await http
        .get(_u('/cameras'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return _decodeList(r)
        .map((e) =>
            CameraNode.fromMap(e as Map<String, dynamic>, baseUrl: cleanBaseUrl))
        .toList();
  }

  Future<CameraNode> addCamera({
    required String name,
    required String url,
    double lat = 43.2389,
    double lon = 76.8897,
  }) async {
    if (offlineDemoMode) {
      throw const ApiException(
        'Добавление RTSP/HLS камеры требует подключения к локальному FastAPI бэкенду.',
      );
    }
    final r = await http
        .post(
          _u('/cameras'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'url': url,
            'lat': lat,
            'lon': lon,
          }),
        )
        .timeout(const Duration(seconds: 8));
    return CameraNode.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<CameraNode> checkCamera(String cameraId) async {
    if (offlineDemoMode) {
      throw const ApiException(
        'Проверка RTSP/HLS потока требует подключения к локальному FastAPI бэкенду.',
      );
    }
    final r = await http
        .post(
          _u('/cameras/$cameraId/check'),
          headers: ngrokHeaders,
        )
        .timeout(const Duration(seconds: 20));
    return CameraNode.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<void> deleteCamera(String cameraId) async {
    if (offlineDemoMode) return;
    final r = await http
        .delete(_u('/cameras/$cameraId'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    _decodeObject(r);
  }

  Future<void> deleteDemoVideo(String videoId) async {
    if (offlineDemoMode) return;
    final r = await http
        .delete(_u('/demo_videos/$videoId'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    _decodeObject(r);
  }

  Future<List<DemoVideoModel>> demoVideos() async {
    if (offlineDemoMode) return LocalDemoStore.instance.demoVideos;
    final r = await http
        .get(_u('/demo_videos'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return _decodeList(r)
        .map((e) => DemoVideoModel.fromMap(
              e as Map<String, dynamic>,
              baseUrl: cleanBaseUrl,
            ))
        .toList();
  }

  Future<DemoVideoModel> uploadDemoVideo({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (offlineDemoMode) {
      throw const ApiException(
        'Загрузка MP4 видео требует подключения к локальному FastAPI бэкенду.',
      );
    }
    final req = http.MultipartRequest('POST', _u('/demo_videos/upload'));
    req.headers.addAll(ngrokHeaders);
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename.isEmpty ? 'demo_upload.mp4' : filename,
    ));
    final streamed = await req.send().timeout(const Duration(seconds: 40));
    final resp = await http.Response.fromStream(streamed);
    return DemoVideoModel.fromMap(
      _decodeObject(resp),
      baseUrl: cleanBaseUrl,
    );
  }

  Future<DetectionResultModel> analyzeDemoVideoFrame({
    required String videoId,
    required double timestampSec,
    bool saveIncident = false,
  }) async {
    if (offlineDemoMode) {
      throw const ApiException(
        'Извлечение кадра FFmpeg и инференция YOLOv8n требуют подключения к локальному бэкенду на Mac.',
      );
    }
    final r = await http
        .post(
          _u('/demo_videos/$videoId/analyze_frame'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'timestamp_sec': timestampSec,
            'save_incident': saveIncident,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return DetectionResultModel.fromMap(
      _decodeObject(r),
      baseUrl: cleanBaseUrl,
    );
  }

  Future<List<DetectionResultModel>> detectionsHistory({int limit = 25}) async {
    if (offlineDemoMode) return const [];
    final r = await http
        .get(_u('/detections', {'limit': '$limit'}), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return _decodeList(r)
        .map((e) => DetectionResultModel.fromMap(
              e as Map<String, dynamic>,
              baseUrl: cleanBaseUrl,
            ))
        .toList();
  }

  Future<List<RiskZone>> riskZones() async {
    if (offlineDemoMode) return LocalDemoStore.instance.riskZones();
    final r = await http
        .get(_u('/risk_zones'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return _decodeList(r)
        .map((e) => RiskZone.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Incident>> incidents({
    String? severity,
    String? status,
    String? type,
    String? query,
  }) async {
    if (offlineDemoMode) {
      return LocalDemoStore.instance.listIncidents(
        severity: severity,
        status: status,
        type: type,
        query: query,
      );
    }
    final q = <String, String>{};
    if (severity != null && severity.isNotEmpty) q['severity'] = severity;
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (type != null && type.isNotEmpty) q['type'] = type;
    if (query != null && query.trim().isNotEmpty) q['q'] = query.trim();
    final r = await http
        .get(_u('/incidents', q), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 8));
    return _decodeList(r)
        .map((e) =>
            Incident.fromMap(e as Map<String, dynamic>, baseUrl: cleanBaseUrl))
        .toList();
  }

  Future<Incident> getIncident(String id) async {
    if (offlineDemoMode) {
      final inc = LocalDemoStore.instance.getIncident(id);
      if (inc == null) throw const ApiException('Инцидент не найден', 404);
      return inc;
    }
    final r = await http
        .get(_u('/incidents/$id'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    return Incident.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<Incident> createIncident({
    required String title,
    required double lat,
    required double lon,
    String severity = 'high',
    String? locationName,
    String? description,
    String? classification,
    double? confidence,
    String? detectionId,
  }) async {
    if (offlineDemoMode) {
      return LocalDemoStore.instance.createManualIncident(
        title: title,
        lat: lat,
        lon: lon,
        severity: severity,
        locationName: locationName,
        description: description,
        classification: classification,
        confidence: confidence,
        detectionId: detectionId,
      );
    }
    final r = await http
        .post(
          _u('/incidents'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'title': title,
            'lat': lat,
            'lon': lon,
            'severity': severity,
            if (locationName != null) 'location_name': locationName,
            if (description != null) 'description': description,
            if (classification != null) 'classification': classification,
            if (confidence != null) 'confidence': confidence,
            if (detectionId != null) 'detection_id': detectionId,
          }),
        )
        .timeout(const Duration(seconds: 8));
    return Incident.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<Incident> updateIncidentStatus(String id, String status) async {
    if (offlineDemoMode) {
      return LocalDemoStore.instance.updateStatus(id, status);
    }
    final r = await http
        .patch(
          _u('/incidents/$id/status'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 6));
    return Incident.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<void> deleteIncident(String id) async {
    if (offlineDemoMode) {
      LocalDemoStore.instance.deleteIncident(id);
      return;
    }
    final r = await http
        .delete(_u('/incidents/$id'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    _decodeObject(r);
  }

  Future<Incident> simulateFire({
    String? cameraId,
    String severity = 'high',
    bool captureFromCamera = false,
  }) async {
    if (offlineDemoMode) {
      return LocalDemoStore.instance
          .simulateFire(cameraId: cameraId, severity: severity);
    }
    final r = await http
        .post(
          _u('/simulate_fire'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            if (cameraId != null && cameraId.isNotEmpty) 'camera_id': cameraId,
            'severity': severity,
            'capture_from_camera': captureFromCamera,
          }),
        )
        .timeout(Duration(seconds: captureFromCamera ? 35 : 10));
    return Incident.fromMap(_decodeObject(r), baseUrl: cleanBaseUrl);
  }

  Future<DetectionResultModel> detectImage({
    required Uint8List bytes,
    required String filename,
    bool saveIncident = false,
    double? lat,
    double? lon,
    String? locationName,
  }) async {
    if (offlineDemoMode) {
      return LocalDemoStore.instance.detectOffline(bytes);
    }
    final req = http.MultipartRequest('POST', _u('/detect'));
    req.headers.addAll(ngrokHeaders);
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename.isEmpty ? 'upload.jpg' : filename,
    ));
    req.fields['save_incident'] = saveIncident ? 'true' : 'false';
    if (lat != null) req.fields['lat'] = '$lat';
    if (lon != null) req.fields['lon'] = '$lon';
    if (locationName != null && locationName.isNotEmpty) {
      req.fields['location_name'] = locationName;
    }

    final streamed = await req.send().timeout(const Duration(seconds: 25));
    final resp = await http.Response.fromStream(streamed);
    return DetectionResultModel.fromMap(
      _decodeObject(resp),
      baseUrl: cleanBaseUrl,
    );
  }

  Future<Uint8List> fetchDemoSampleImage(String kind) async {
    final r = await http
        .get(_u('/demo_samples/$kind'), headers: ngrokHeaders)
        .timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) {
      throw ApiException(
        'Не удалось загрузить тестовый образец ($kind)',
        r.statusCode,
      );
    }
    return r.bodyBytes;
  }

  Future<Map<String, dynamic>> registerDevice(
    String token, {
    String name = 'iPhone',
  }) async {
    if (offlineDemoMode) {
      return {'ok': true, 'devices': 1, 'firebase': 'offline_demo'};
    }
    final r = await http
        .post(
          _u('/register_device'),
          headers: {...ngrokHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': token,
            'name': name,
            'platform': 'ios',
          }),
        )
        .timeout(const Duration(seconds: 6));
    return _decodeObject(r);
  }
}
