import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/incident.dart';
import '../screens/incident_screen.dart';
import '../theme/app_theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class PushService {
  PushService._();
  static final instance = PushService._();

  bool _firebaseInitialized = false;
  String? _initError;

  bool get isFirebaseAvailable => _firebaseInitialized;
  String? get initError => _initError;

  Future<void> init() async {
    const firebaseEnabled =
        bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: false);
    if (!firebaseEnabled) {
      _firebaseInitialized = false;
      _initError =
          'Firebase не настроен (нет GoogleService-Info.plist). Работают локальные in-app уведомления.';
      debugPrint('[FireWatch PushService] $_initError');
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseInitialized = true;
    } catch (e) {
      _firebaseInitialized = false;
      _initError =
          'Firebase не настроен (нет GoogleService-Info.plist). Работают локальные in-app уведомления.';
      debugPrint('[FireWatch PushService] $_initError ($e)');
      return;
    }

    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

      final initial = await fm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openFromMessage(initial));
      }

      FirebaseMessaging.onMessage.listen((m) {
        final inc = Incident.fromMap(m.data);
        if (!inc.isValid) return;
        showInAppIncidentBanner(
          inc,
          customTitle: m.notification?.title,
        );
      });
    } catch (e) {
      _initError = 'FCM инициализирован частично: $e';
      debugPrint('[FireWatch PushService] $_initError');
    }
  }

  Future<String?> getToken() async {
    if (!_firebaseInitialized) return null;
    try {
      final fm = FirebaseMessaging.instance;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        for (var i = 0; i < 6; i++) {
          if (await fm.getAPNSToken() != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      return await fm.getToken();
    } catch (e) {
      debugPrint('[FireWatch PushService] getToken error: $e');
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _firebaseInitialized
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream.empty();

  void _openFromMessage(RemoteMessage m) {
    final inc = Incident.fromMap(m.data);
    if (inc.isValid) openIncident(inc);
  }

  void showInAppIncidentBanner(
    Incident inc, {
    String? customTitle,
    bool enabled = true,
  }) {
    if (!enabled) return;
    final state = messengerKey.currentState;
    if (state == null) return;
    final sevColor = AppColors.forSeverity(inc.severity);
    state
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: AppColors.cardElevated,
          dividerColor: AppColors.cardBorder,
          leading: Icon(CupertinoIcons.flame_fill, color: sevColor, size: 26),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                customTitle ??
                    (inc.isDemo
                        ? '[DEMO] ${inc.title}'
                        : inc.title),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${AppColors.severityLabel(inc.severity)} · '
                '${inc.lat.toStringAsFixed(4)}, ${inc.lon.toStringAsFixed(4)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => state.hideCurrentMaterialBanner(),
              child: const Text(
                'DISMISS',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerRed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () {
                state.hideCurrentMaterialBanner();
                openIncident(inc);
              },
              child: const Text('OPEN'),
            ),
          ],
        ),
      );
  }

  void openIncident(Incident inc) {
    navigatorKey.currentState?.push(
      CupertinoPageRoute(builder: (_) => IncidentScreen(incident: inc)),
    );
  }
}
