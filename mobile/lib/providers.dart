import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/incident.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';

// Simulator loopback is deterministic. A physical iPhone must use the Mac's
// current LAN address, entered in Settings; LAN IPs can change between networks.
const defaultSimulatorBackendUrl = 'http://127.0.0.1:8000';
const defaultMacLanBackendUrl = defaultSimulatorBackendUrl;
const secondaryMacLanBackendUrl = defaultSimulatorBackendUrl;

const List<String> candidateBackendUrls = [defaultSimulatorBackendUrl];

bool isLoopbackUrl(String url) {
  final u = url.toLowerCase();
  return u.contains('://127.0.0.1') || u.contains('://localhost');
}

/// Переопределяется в main() после SharedPreferences.getInstance().
final sharedPrefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError());

const _kServerUrl = 'server_url';
const _kOfflineDemoMode = 'offline_demo_mode';
const _kInAppNotifications = 'in_app_notifications';
const _kReadIncidentIds = 'read_incident_ids';
const _kProfileName = 'profile_name';
const _kProfileRole = 'profile_role';
const _kProfileUnit = 'profile_unit';
const _kLastConnectedAt = 'last_connected_at';

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.read(sharedPrefsProvider);
    final saved = prefs.getString(_kServerUrl)?.trim();
    if (saved == null || saved.isEmpty) {
      return defaultMacLanBackendUrl;
    }
    // Migrate old hard-coded development addresses to the simulator default.
    // A physical iPhone should be configured with the Mac's current LAN IP in Settings.
    final isLegacyHardcodedAddress = saved.contains('192.168.1.101') ||
        saved.contains('10.204.57.18') ||
        saved.contains('10.2.68.203');
    if (isLegacyHardcodedAddress) {
      prefs.setString(_kServerUrl, defaultSimulatorBackendUrl);
      return defaultSimulatorBackendUrl;
    }
    return saved;
  }

  Future<void> set(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    final target = clean.isEmpty ? defaultMacLanBackendUrl : clean;
    await ref.read(sharedPrefsProvider).setString(_kServerUrl, target);
    state = target;
  }
}

final serverUrlProvider =
    NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class OfflineDemoModeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(_kOfflineDemoMode) ?? false;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPrefsProvider).setBool(_kOfflineDemoMode, enabled);
    state = enabled;
  }
}

final offlineDemoModeProvider =
    NotifierProvider<OfflineDemoModeNotifier, bool>(
        OfflineDemoModeNotifier.new);

class InAppNotificationsNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPrefsProvider).getBool(_kInAppNotifications) ?? true;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPrefsProvider).setBool(_kInAppNotifications, enabled);
    state = enabled;
  }
}

final inAppNotificationsProvider =
    NotifierProvider<InAppNotificationsNotifier, bool>(
        InAppNotificationsNotifier.new);

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final prefs = ref.read(sharedPrefsProvider);
    return UserProfile(
      name: prefs.getString(_kProfileName) ?? 'Alizhan T.',
      role: prefs.getString(_kProfileRole) ?? 'Duty Ranger / Dispatcher',
      unit: prefs.getString(_kProfileUnit) ?? 'Forestry Monitoring Sector #4',
    );
  }

  Future<void> update({
    required String name,
    required String role,
    required String unit,
  }) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_kProfileName, name.trim());
    await prefs.setString(_kProfileRole, role.trim());
    await prefs.setString(_kProfileUnit, unit.trim());
    state = UserProfile(
      name: name.trim(),
      role: role.trim(),
      unit: unit.trim(),
    );
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);

class ReadIncidentsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final list =
        ref.read(sharedPrefsProvider).getStringList(_kReadIncidentIds) ??
            const [];
    return list.toSet();
  }

  Future<void> markRead(String id) async {
    if (state.contains(id)) return;
    final next = {...state, id};
    state = next;
    await ref
        .read(sharedPrefsProvider)
        .setStringList(_kReadIncidentIds, next.toList());
  }

  Future<void> toggleRead(String id) async {
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    await ref
        .read(sharedPrefsProvider)
        .setStringList(_kReadIncidentIds, next.toList());
  }

  Future<void> markAllRead(Iterable<String> ids) async {
    final next = {...state, ...ids};
    state = next;
    await ref
        .read(sharedPrefsProvider)
        .setStringList(_kReadIncidentIds, next.toList());
  }
}

final readIncidentsProvider =
    NotifierProvider<ReadIncidentsNotifier, Set<String>>(
        ReadIncidentsNotifier.new);

class NavigationTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final navigationTabProvider =
    NotifierProvider<NavigationTabNotifier, int>(NavigationTabNotifier.new);

/// 0 = Video Monitoring (Live Cameras), 1 = AI Detection Scanner
class CamerasSubTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setMode(int mode) => state = mode;
}

final camerasSubTabProvider =
    NotifierProvider<CamerasSubTabNotifier, int>(CamerasSubTabNotifier.new);

class SelectedCameraIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedCameraIdProvider =
    NotifierProvider<SelectedCameraIdNotifier, String?>(
        SelectedCameraIdNotifier.new);

final apiProvider = Provider<ApiService>((ref) {
  final url = ref.watch(serverUrlProvider);
  final offlineDemo = ref.watch(offlineDemoModeProvider);
  return ApiService(url, offlineDemoMode: offlineDemo);
});

/// Real-time Backend Connection & Diagnostics state (never fakes Connected).
class BackendConnectionState {
  const BackendConnectionState({
    this.isConnected = false,
    this.isChecking = false,
    this.latencyMs,
    this.lastCheckedAt,
    this.lastSuccessAt,
    this.lastError,
    this.detectorMode,
    this.detectorModelName,
    this.report,
  });

  final bool isConnected;
  final bool isChecking;
  final int? latencyMs;
  final DateTime? lastCheckedAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final String? detectorMode;
  final String? detectorModelName;
  final BackendDiagnosticsReport? report;

  BackendConnectionState copyWith({
    bool? isConnected,
    bool? isChecking,
    int? latencyMs,
    DateTime? lastCheckedAt,
    DateTime? lastSuccessAt,
    String? lastError,
    bool clearError = false,
    String? detectorMode,
    String? detectorModelName,
    BackendDiagnosticsReport? report,
  }) {
    return BackendConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      latencyMs: latencyMs ?? this.latencyMs,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      detectorMode: detectorMode ?? this.detectorMode,
      detectorModelName: detectorModelName ?? this.detectorModelName,
      report: report ?? this.report,
    );
  }
}

class BackendConnectionNotifier extends Notifier<BackendConnectionState> {
  @override
  BackendConnectionState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final savedTs = prefs.getString(_kLastConnectedAt);
    final lastSuccess =
        savedTs != null ? DateTime.tryParse(savedTs)?.toLocal() : null;
    return BackendConnectionState(lastSuccessAt: lastSuccess);
  }

  /// Non-blocking startup health probe with automatic multi-IP LAN discovery.
  Future<bool> checkHealth({bool allowAutoFallback = false}) async {
    if (state.isChecking) return state.isConnected;
    state = state.copyWith(isChecking: true);

    final currentUrl = ref.read(serverUrlProvider);
    final api = ApiService(currentUrl, offlineDemoMode: false);

    try {
      final res = await api.probeLiveHealth(
        timeout: const Duration(milliseconds: 2800),
      );
      final now = DateTime.now();
      await ref
          .read(sharedPrefsProvider)
          .setString(_kLastConnectedAt, now.toIso8601String());
      final det = (res.data['detector'] as Map?)?.cast<String, dynamic>();
      state = state.copyWith(
        isConnected: true,
        isChecking: false,
        latencyMs: res.latencyMs,
        lastCheckedAt: now,
        lastSuccessAt: now,
        clearError: true,
        detectorMode: det?['mode']?.toString(),
        detectorModelName: det?['model_name']?.toString(),
      );
      return true;
    } catch (primaryErr) {
      if (allowAutoFallback) {
        for (final candidate in candidateBackendUrls) {
          if (candidate == currentUrl) continue;
          try {
            final probeApi = ApiService(candidate, offlineDemoMode: false);
            final res = await probeApi.probeLiveHealth(
              timeout: const Duration(milliseconds: 2200),
            );
            final now = DateTime.now();
            await ref.read(serverUrlProvider.notifier).set(candidate);
            await ref
                .read(sharedPrefsProvider)
                .setString(_kLastConnectedAt, now.toIso8601String());
            final det =
                (res.data['detector'] as Map?)?.cast<String, dynamic>();
            state = state.copyWith(
              isConnected: true,
              isChecking: false,
              latencyMs: res.latencyMs,
              lastCheckedAt: now,
              lastSuccessAt: now,
              clearError: true,
              detectorMode: det?['mode']?.toString(),
              detectorModelName: det?['model_name']?.toString(),
            );
            return true;
          } catch (_) {
            // Try next candidate
          }
        }
      }

      final humanErr = formatHumanReadableNetworkError(primaryErr, currentUrl);
      state = state.copyWith(
        isConnected: false,
        isChecking: false,
        lastCheckedAt: DateTime.now(),
        lastError: humanErr,
      );
      return false;
    }
  }

  /// Full diagnostic probe across /health, /cameras, /incidents, and /stats.
  Future<BackendDiagnosticsReport> runFullDiagnostics() async {
    state = state.copyWith(isChecking: true);
    final url = ref.read(serverUrlProvider);
    final offlineDemo = ref.read(offlineDemoModeProvider);
    final api = ApiService(url, offlineDemoMode: offlineDemo);
    final report = await api.runDiagnostics();
    final now = DateTime.now();
    if (report.isConnected) {
      await ref
          .read(sharedPrefsProvider)
          .setString(_kLastConnectedAt, now.toIso8601String());
    }
    state = state.copyWith(
      isConnected: report.isConnected,
      isChecking: false,
      latencyMs: report.responseTimeMs,
      lastCheckedAt: now,
      lastSuccessAt: report.isConnected ? now : state.lastSuccessAt,
      lastError: report.lastError,
      clearError: report.isConnected,
      detectorMode: report.detectorMode,
      detectorModelName: report.detectorModelName,
      report: report,
    );
    return report;
  }
}

final backendConnectionProvider =
    NotifierProvider<BackendConnectionNotifier, BackendConnectionState>(
        BackendConnectionNotifier.new);

final statsProvider = FutureProvider<SystemStats>((ref) async {
  final stats = await ref.watch(apiProvider).stats();
  return stats;
});

final camerasProvider = FutureProvider<List<CameraNode>>((ref) {
  return ref.watch(apiProvider).cameras();
});

final demoVideosProvider = FutureProvider<List<DemoVideoModel>>((ref) {
  return ref.watch(apiProvider).demoVideos();
});

final detectionsHistoryProvider =
    FutureProvider<List<DetectionResultModel>>((ref) {
  return ref.watch(apiProvider).detectionsHistory(limit: 25);
});

final riskZonesProvider = FutureProvider<List<RiskZone>>((ref) {
  return ref.watch(apiProvider).riskZones();
});

final incidentsProvider = FutureProvider<List<Incident>>((ref) {
  return ref.watch(apiProvider).incidents();
});

final unreadAlertsCountProvider = Provider<int>((ref) {
  final incidentsAsync = ref.watch(incidentsProvider);
  final readIds = ref.watch(readIncidentsProvider);
  return incidentsAsync.maybeWhen(
    data: (list) =>
        list.where((i) => !readIds.contains(i.id) && i.status == 'new').length,
    orElse: () => 0,
  );
});

final fcmTokenProvider =
    FutureProvider<String?>((_) => PushService.instance.getToken());

enum RegStatus { idle, loading, ok, error }

class RegistrationState {
  const RegistrationState(this.status, [this.message]);
  final RegStatus status;
  final String? message;
}

class RegistrationNotifier extends Notifier<RegistrationState> {
  @override
  RegistrationState build() => const RegistrationState(RegStatus.idle);

  Future<void> register() async {
    final url = ref.read(serverUrlProvider);
    if (url.isEmpty) {
      state = const RegistrationState(RegStatus.error, 'Укажите URL сервера');
      return;
    }
    state = const RegistrationState(RegStatus.loading);
    try {
      final token = await ref.read(fcmTokenProvider.future);
      if (token == null || token.isEmpty) {
        state = const RegistrationState(
          RegStatus.error,
          'FCM-токен недоступен (Firebase не настроен или запуск в iOS Simulator). Локальные in-app уведомления работают.',
        );
        return;
      }
      final profile = ref.read(userProfileProvider);
      await ref.read(apiProvider).registerDevice(token, name: profile.name);
      state = const RegistrationState(
        RegStatus.ok,
        'Устройство зарегистрировано на сервере для FCM-пушей',
      );
    } catch (e) {
      state = RegistrationState(RegStatus.error, '$e');
    }
  }
}

final registrationProvider =
    NotifierProvider<RegistrationNotifier, RegistrationState>(
        RegistrationNotifier.new);

void refreshAllFireWatchData(WidgetRef ref) {
  ref.invalidate(statsProvider);
  ref.invalidate(incidentsProvider);
  ref.invalidate(riskZonesProvider);
  ref.invalidate(camerasProvider);
  ref.invalidate(demoVideosProvider);
  ref.invalidate(detectionsHistoryProvider);
}
