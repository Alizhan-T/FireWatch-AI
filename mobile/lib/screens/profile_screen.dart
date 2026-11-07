import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'diagnostics_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    _nameCtrl = TextEditingController(text: profile.name);
    _roleCtrl = TextEditingController(text: profile.role);
    _unitCtrl = TextEditingController(text: profile.unit);
    _urlCtrl = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _unitCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    await ref.read(userProfileProvider.notifier).update(
          name: _nameCtrl.text,
          role: _roleCtrl.text,
          unit: _unitCtrl.text,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Operator profile saved')),
    );
  }

  Future<void> _applyUrlAndReconnect([String? preset]) async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    if (preset != null) {
      _urlCtrl.text = preset;
    }
    await ref.read(serverUrlProvider.notifier).set(_urlCtrl.text);
    await ref.read(offlineDemoModeProvider.notifier).set(false);
    final ok = await ref
        .read(backendConnectionProvider.notifier)
        .checkHealth(allowAutoFallback: preset == null);
    _urlCtrl.text = ref.read(serverUrlProvider);
    refreshAllFireWatchData(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.cardElevated : AppColors.dangerRed,
        content: Text(
          ok
              ? 'Connected to ${ref.read(serverUrlProvider)}'
              : 'Could not reach ${ref.read(serverUrlProvider)}',
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    await ref.read(serverUrlProvider.notifier).set(_urlCtrl.text);
    final report =
        await ref.read(backendConnectionProvider.notifier).runFullDiagnostics();
    if (report.isConnected) {
      refreshAllFireWatchData(ref);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            report.isConnected ? AppColors.cardElevated : AppColors.dangerRed,
        content: Text(
          report.isConnected
              ? 'Connection verified (${report.responseTimeMs} ms)'
              : 'Connection failed: ${report.lastError ?? "Unreachable"}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offlineDemo = ref.watch(offlineDemoModeProvider);
    final inAppNotif = ref.watch(inAppNotificationsProvider);
    final reg = ref.watch(registrationProvider);
    final tokenAsync = ref.watch(fcmTokenProvider);
    final statsAsync = ref.watch(statsProvider);
    final profile = ref.watch(userProfileProvider);
    final conn = ref.watch(backendConnectionProvider);
    final currentUrl = ref.watch(serverUrlProvider);

    if (_urlCtrl.text != currentUrl && !FocusScope.of(context).hasFocus) {
      _urlCtrl.text = currentUrl;
    }

    final initials = profile.name.trim().isNotEmpty
        ? profile.name.trim().substring(0, 1).toUpperCase()
        : 'A';

    final connColor = conn.isConnected
        ? AppColors.primaryGreen
        : (offlineDemo ? AppColors.warningOrange : AppColors.dangerRed);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            // Top Apple Settings Large Title
            const Text(
              'Profile & Settings',
              style: TextStyle(
                fontFamily: AppTheme.iosDisplayFamily,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 16),

            // 1. BACKEND CONNECTION BLOCK (Priority #1)
            IosSectionHeader(
              title: 'Backend Connection',
              icon: CupertinoIcons.cloud,
              actionLabel: 'Diagnostics',
              onAction: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const DiagnosticsScreen(),
                  ),
                );
              },
            ),
            IosSurfaceCard(
              padding: const EdgeInsets.all(16),
              borderColor: connColor.withValues(alpha: 0.38),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Header Row
                  Row(
                    children: [
                      AppIconBadge(
                        icon: conn.isConnected
                            ? CupertinoIcons.checkmark_shield_fill
                            : CupertinoIcons.wifi_exclamationmark,
                        color: connColor,
                        boxSize: 34,
                        iconSize: 18,
                        borderRadius: 10,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conn.isConnected
                                  ? 'Connected'
                                  : (offlineDemo
                                      ? 'Disconnected (Demo)'
                                      : 'Disconnected'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                                color: connColor,
                              ),
                            ),
                            Text(
                              conn.lastSuccessAt != null
                                  ? 'Last check: ${formatRelativeOrShortTime(conn.lastSuccessAt!)}'
                                  : 'Not verified yet',
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
                      if (conn.latencyMs != null && conn.isConnected) ...[
                        const SizedBox(width: 8),
                        IosStatusPill(
                          label: '${conn.latencyMs} ms',
                          color: AppColors.primaryGreen,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Server URL Input (Cupertino)
                  CupertinoTextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    placeholder: 'http://192.168.1.101:8000',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: AppIcon(
                        CupertinoIcons.link,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    suffix: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Clipboard.setData(
                          ClipboardData(text: _urlCtrl.text.trim()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backend URL copied to clipboard'),
                          ),
                        );
                      },
                      child: const Text(
                        'Copy URL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryAccent,
                        ),
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),

                  if (isLoopbackUrl(currentUrl)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warningOrange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color:
                              AppColors.warningOrange.withValues(alpha: 0.40),
                        ),
                      ),
                      child: const Text(
                        '127.0.0.1 / localhost works on iOS Simulator only. Use Mac Wi-Fi IP (192.168.1.101:8000) on physical iPhone.',
                        style: TextStyle(
                          color: AppColors.warningOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  if (!conn.isConnected &&
                      conn.lastError != null &&
                      conn.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: AppColors.dangerRed.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        conn.lastError!,
                        style: const TextStyle(
                          color: AppColors.dangerRed,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  // Test Connection & Reconnect Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              conn.isChecking ? null : _testConnection,
                          icon: conn.isChecking
                              ? const CupertinoActivityIndicator(
                                  radius: 8,
                                  color: Colors.black,
                                )
                              : const AppIcon(
                                  CupertinoIcons.checkmark_seal_fill,
                                  size: 16,
                                  color: Colors.white,
                                ),
                          label: const Text('Test Connection'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: conn.isChecking
                              ? null
                              : () => _applyUrlAndReconnect(),
                          icon: const AppIcon(
                            CupertinoIcons.refresh,
                            size: 15,
                          ),
                          label: const Text('Reconnect'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quick IP Presets
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _applyUrlAndReconnect(defaultMacLanBackendUrl),
                          icon: const AppIcon(CupertinoIcons.wifi, size: 14),
                          label: const Text(
                            'Mac Wi-Fi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _applyUrlAndReconnect(defaultSimulatorBackendUrl),
                          icon: const AppIcon(
                            CupertinoIcons.device_phone_portrait,
                            size: 14,
                          ),
                          label: const Text(
                            'Simulator',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),

                  // Open Backend Diagnostics Screen Row
                  IosPressable(
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          AppIconBadge(
                            icon: CupertinoIcons.speedometer,
                            color: AppColors.primaryGreen,
                            boxSize: 30,
                            iconSize: 16,
                            borderRadius: 9,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Backend Diagnostics',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Inspect /health, /cameras, /incidents & response latency',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppIcon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),

                  // Offline Demo Mode Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Offline Demo Mode',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Operate autonomously with local demo store',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoSwitch(
                        value: offlineDemo,
                        activeTrackColor: AppColors.warningOrange,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          await ref
                              .read(offlineDemoModeProvider.notifier)
                              .set(v);
                          refreshAllFireWatchData(ref);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 2. OPERATOR PROFILE CARD
            const IosSectionHeader(
              title: 'Operator Profile',
              icon: CupertinoIcons.person_crop_circle,
            ),
            IosSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.cardElevated,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                AppColors.primaryGreen.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontFamily: AppTheme.iosDisplayFamily,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16.5,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${profile.role} · ${profile.unit}',
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
                    ],
                  ),
                  const SizedBox(height: 14),
                  CupertinoTextField(
                    controller: _nameCtrl,
                    placeholder: 'Operator Name',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _roleCtrl,
                    placeholder: 'Role',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _unitCtrl,
                    placeholder: 'Monitoring Unit',
                    padding: const EdgeInsets.all(13),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saveProfile,
                    icon: const AppIcon(
                      CupertinoIcons.checkmark_alt,
                      size: 17,
                      color: Colors.white,
                    ),
                    label: const Text('Save Profile'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 3. NOTIFICATION SETTINGS
            const IosSectionHeader(
              title: 'Notifications',
              icon: CupertinoIcons.bell,
            ),
            IosSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'In-App Incident Banners',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Show instant alert banner on new fire events',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoSwitch(
                        value: inAppNotif,
                        activeTrackColor: AppColors.primaryGreen,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          ref
                              .read(inAppNotificationsProvider.notifier)
                              .set(v);
                        },
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      AppIcon(
                        PushService.instance.isFirebaseAvailable
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.info_circle,
                        size: 16,
                        color: PushService.instance.isFirebaseAvailable
                            ? AppColors.primaryGreen
                            : AppColors.warningOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          PushService.instance.isFirebaseAvailable
                              ? 'Firebase Cloud Messaging: Connected'
                              : (PushService.instance.initError ??
                                  'FCM not configured (In-App alerts active)'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  tokenAsync.maybeWhen(
                    data: (t) => t == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Token: ${t.substring(0, t.length.clamp(0, 24))}…',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: reg.status == RegStatus.loading
                        ? null
                        : () =>
                            ref.read(registrationProvider.notifier).register(),
                    icon: const AppIcon(CupertinoIcons.bell_circle, size: 16),
                    label: const Text('Register Device for Push'),
                  ),
                  if (reg.message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      reg.message!,
                      style: TextStyle(
                        fontSize: 12,
                        color: reg.status == RegStatus.ok
                            ? AppColors.primaryGreen
                            : AppColors.warningOrange,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 4. SYSTEM & AI ENGINE INFO
            const IosSectionHeader(
              title: 'About FireWatch AI',
              icon: CupertinoIcons.info_circle,
            ),
            IosSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Version',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        '1.0.0 (iOS Native Edition)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  statsAsync.maybeWhen(
                    data: (s) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'CV Engine',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                s.detectorModelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1),
                        ),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const Text(
                    'All simulated fire events and heuristic fallbacks are explicitly labeled DEMO and never represented as live emergency telemetry.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
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
