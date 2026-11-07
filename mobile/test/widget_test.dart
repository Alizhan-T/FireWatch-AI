import 'package:firewatch/main.dart';
import 'package:firewatch/models/incident.dart';
import 'package:firewatch/providers.dart';
import 'package:firewatch/services/api_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Incident, CameraNode, SystemStats & DetectionResultModel parse backend JSON', () {
    final inc = Incident.fromMap(
      {
        'id': 'inc_20261031_abc123',
        'title': 'AI Detection: Fire',
        'source': 'detection',
        'lat': 53.0833,
        'lon': 70.3000,
        'severity': 'critical',
        'status': 'new',
        'classification': 'fire_smoke',
        'confidence': 0.87,
        'detection_mode': 'real_model',
        'media_type': 'image',
        'media_url': '/media/uploads/det_1.jpg',
        'is_demo': false,
        'created_at': '2026-10-31T13:00:00+00:00',
        'updated_at': '2026-10-31T13:00:00+00:00',
      },
      baseUrl: 'http://192.168.1.101:8000',
    );

    expect(inc.id, 'inc_20261031_abc123');
    expect(inc.severity, 'critical');
    expect(inc.detectionMode, 'real_model');
    expect(inc.confidence, 0.87);
    expect(inc.isDemo, isFalse);
    expect(inc.mediaUrl, 'http://192.168.1.101:8000/media/uploads/det_1.jpg');

    final cam = CameraNode.fromMap(
      {
        'id': 'cam_1',
        'name': 'North Sector Tower',
        'url': 'rtsp://192.168.1.50:554/stream1',
        'lat': 43.25,
        'lon': 76.95,
        'status': 'offline',
        'last_error': 'Connection refused',
        'snapshot_url': '/media/snapshots/cam_1.jpg',
      },
      baseUrl: 'http://192.168.1.101:8000',
    );
    expect(cam.isOffline, isTrue);
    expect(cam.lastError, 'Connection refused');
    expect(
      cam.snapshotUrl,
      'http://192.168.1.101:8000/media/snapshots/cam_1.jpg',
    );

    final stats = SystemStats.fromMap({
      'incidents': {'total': 3, 'active': 2, 'last_24h': 3, 'demo': 1},
      'detections': {
        'total': 5,
        'by_classification': {'fire': 2, 'smoke': 1, 'none': 2},
        'by_mode': {'real_model': 5},
        'avg_processing_ms': 95,
      },
      'fire_detections': 2,
      'smoke_detections': 1,
      'clear_detections': 2,
      'high_risk_zones': 1,
      'cameras_configured': 0,
      'cameras_online': 0,
      'demo_videos_available': 2,
      'detector': {
        'mode': 'real_model',
        'provider': 'ultralytics-yolov8',
        'model_name': 'YOLOv8n (fire_smoke_yolov8n.pt)',
      },
      'latest_detection': {
        'id': 'det_1',
        'classification': 'fire',
        'confidence': 0.82,
        'mode': 'real_model',
        'source_video_id': 'demo_wildfire_active',
        'frame_timestamp_sec': 1.2,
        'created_at': '2026-10-31T13:05:00+00:00',
      },
    });
    expect(stats.isRealModel, isTrue);
    expect(stats.fireDetections, 2);
    expect(stats.smokeDetections, 1);
    expect(stats.clearDetections, 2);
    expect(stats.latestDetection?.classification, 'fire');
  });

  test('LocalDemoStore incident lifecycle (create, filter, search, status update, delete) & network error formatter', () {
    final store = LocalDemoStore.instance;
    final created = store.createManualIncident(
      title: 'Test Wildfire Alpha',
      lat: 53.08,
      lon: 70.30,
      severity: 'critical',
      locationName: 'Burabay North',
      classification: 'fire',
      confidence: 0.91,
    );
    expect(
      store.listIncidents(type: 'fire', query: 'Alpha').map((e) => e.id),
      contains(created.id),
    );
    expect(
      store.listIncidents(type: 'smoke', query: 'Alpha'),
      isEmpty,
    );

    final updated = store.updateStatus(created.id, 'acknowledged');
    expect(updated.status, 'acknowledged');

    store.deleteIncident(created.id);
    expect(store.getIncident(created.id), isNull);

    final loopbackMsg = formatHumanReadableNetworkError(
      Exception('SocketException'),
      'http://127.0.0.1:8000',
    );
    expect(loopbackMsg, contains('192.168.1.101:8000'));
  });

  testWidgets(
    'FireWatchApp renders native iOS UI, simulates fire in Demo Mode, and navigates all 5 tabs + Diagnostics',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'offline_demo_mode': true,
        'server_url': 'http://192.168.1.101:8000',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: const FireWatchApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Dashboard (Home tab) is visible with FOREST SAFETY STATUS hero & telemetry
      expect(find.text('FireWatch AI'), findsOneWidget);
      expect(find.text('FOREST SAFETY STATUS'), findsOneWidget);
      expect(find.text('Active Incidents'), findsOneWidget);
      expect(find.text('Demo Videos'), findsOneWidget);
      expect(find.text('AI Detections'), findsOneWidget);
      expect(find.text('Risk Zones'), findsOneWidget);
      expect(find.text('YOLOv8n Detection Telemetry'), findsOneWidget);

      // 2. Scroll to and tap SIMULATE FIRE (DEMO) button
      final simBtn = find.text('SIMULATE FIRE (DEMO)');
      await tester.scrollUntilVisible(
        simBtn,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(simBtn);
      await tester.pumpAndSettle();
      expect(simBtn, findsOneWidget);
      await tester.tap(simBtn);
      await tester.pumpAndSettle();

      // Verify incident was generated in demo store
      expect(LocalDemoStore.instance.listIncidents().isNotEmpty, isTrue);

      // Dismiss in-app banner if visible
      if (find.text('DISMISS').evaluate().isNotEmpty) {
        await tester.tap(find.text('DISMISS'));
        await tester.pumpAndSettle();
      }

      // 3. Navigate to Cameras tab -> verify DEMO VIDEO, REAL CAMERAS, and AI PHOTO modes
      await tester.tap(find.text('Cameras'));
      await tester.pumpAndSettle();
      expect(find.text('Local Video Demo'), findsOneWidget);
      expect(find.text('DEMO VIDEO'), findsWidgets);
      expect(
        find.text('Extract & Analyze Frame (FFmpeg + YOLOv8n)'),
        findsOneWidget,
      );

      // Switch to REAL CAMERAS segmented tab -> verify honest empty state
      await tester.tap(find.text('REAL CAMERAS'));
      await tester.pumpAndSettle();
      expect(find.text('Real Cameras (RTSP/HLS)'), findsOneWidget);
      expect(
        find.text('No Real RTSP / HLS Cameras Configured'),
        findsOneWidget,
      );
      expect(find.text('Add RTSP / HLS Camera'), findsOneWidget);

      // Switch to AI PHOTO segmented tab
      await tester.tap(find.text('AI PHOTO'));
      await tester.pumpAndSettle();
      expect(find.text('AI Image Scanner'), findsOneWidget);
      expect(find.text('Run YOLOv8n Analysis'), findsOneWidget);

      // 4. Navigate to Incidents tab and verify simulated incident is listed
      await tester.tap(find.text('Incidents'));
      await tester.pumpAndSettle();
      expect(find.text('Incident Alerts'), findsOneWidget);
      expect(find.textContaining('Симуляция (Offline Demo)'), findsWidgets);

      // 5. Navigate to Settings tab & open Backend Diagnostics
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Profile & Settings'), findsOneWidget);
      expect(find.text('Backend Connection'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Backend Diagnostics'), findsOneWidget);

      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('Connection Telemetry'), findsOneWidget);
      expect(find.text('Endpoint Health Probes'), findsOneWidget);
      expect(find.text('FFmpeg Video Engine'), findsOneWidget);
      expect(find.text('SQLite Database'), findsOneWidget);
    },
  );
}
