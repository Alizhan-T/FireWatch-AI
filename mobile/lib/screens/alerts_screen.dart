import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/incident.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/ios_components.dart';
import 'incident_screen.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all' | 'fire' | 'smoke'
  String _statusFilter = 'all'; // 'all' | 'new' | 'acknowledged' | 'resolved' | 'false_alarm'
  String _severityFilter = 'all';
  bool _unreadOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteIncident(Incident inc) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Incident?'),
        content: Text(
          'Remove "${inc.title}" from the SQLite database? This action cannot be undone.',
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
      await ref.read(apiProvider).deleteIncident(inc.id);
      refreshAllFireWatchData(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incident deleted from SQLite')),
      );
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

  String _dateGroupLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(itemDay).inDays;
    if (diffDays <= 0) return 'TODAY';
    if (diffDays == 1) return 'YESTERDAY';
    return 'EARLIER';
  }

  @override
  Widget build(BuildContext context) {
    final incidentsAsync = ref.watch(incidentsProvider);
    final readIds = ref.watch(readIncidentsProvider);

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
                refreshAllFireWatchData(ref);
                await ref.read(incidentsProvider.future);
              },
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Top iOS Large Title Header
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Incident Alerts',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.iosDisplayFamily,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          incidentsAsync.maybeWhen(
                            data: (list) => list.isEmpty
                                ? const SizedBox.shrink()
                                : CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(readIncidentsProvider.notifier)
                                          .markAllRead(list.map((e) => e.id));
                                    },
                                    child: const Text(
                                      'Mark All Read',
                                      style: TextStyle(
                                        color: AppColors.primaryGreen,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          IosPressable(
                            onTap: () => refreshAllFireWatchData(ref),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cardBorder,
                                  width: 0.5,
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.refresh,
                                size: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Native iOS Search Field
                  CupertinoSearchTextField(
                    controller: _searchCtrl,
                    placeholder: 'Search incidents by title, sector, or ID…',
                    backgroundColor: AppColors.secondaryBackground,
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
                  const SizedBox(height: 12),

                  // Type Segmented Control: All | Fire | Smoke
                  CupertinoSlidingSegmentedControl<String>(
                    groupValue: _typeFilter,
                    backgroundColor: AppColors.secondaryBackground,
                    thumbColor: AppColors.cardElevated,
                    children: const {
                      'all': Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          'All Types',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      'fire': Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          'Fire',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      'smoke': Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          'Smoke',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    },
                    onValueChanged: (v) {
                      if (v != null) {
                        HapticFeedback.selectionClick();
                        setState(() => _typeFilter = v);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // Compact iOS Status & Severity Filter Strip
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _FilterCapsule(
                          label: 'Unread',
                          selected: _unreadOnly,
                          activeColor: AppColors.primaryGreen,
                          onTap: () =>
                              setState(() => _unreadOnly = !_unreadOnly),
                        ),
                        const SizedBox(width: 8),
                        for (final st in [
                          'all',
                          'new',
                          'acknowledged',
                          'resolved',
                          'false_alarm',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _FilterCapsule(
                              label: st == 'all'
                                  ? 'All Status'
                                  : AppColors.statusLabel(st),
                              selected: _statusFilter == st,
                              activeColor: AppColors.primaryAccent,
                              onTap: () => setState(() => _statusFilter = st),
                            ),
                          ),
                        for (final sev in ['critical', 'high', 'medium', 'low'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _FilterCapsule(
                              label: sev.toUpperCase(),
                              selected: _severityFilter == sev,
                              activeColor: AppColors.forSeverity(sev),
                              onTap: () => setState(() {
                                _severityFilter =
                                    _severityFilter == sev ? 'all' : sev;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Grouped Alerts List
                  incidentsAsync.when(
                    data: (all) {
                      final q = _searchQuery.trim().toLowerCase();
                      final filtered = all.where((inc) {
                        if (_severityFilter != 'all' &&
                            inc.severity != _severityFilter) {
                          return false;
                        }
                        if (_statusFilter != 'all' &&
                            inc.status != _statusFilter) {
                          return false;
                        }
                        if (_typeFilter != 'all') {
                          final cls = (inc.classification ?? '').toLowerCase();
                          if (_typeFilter == 'fire' &&
                              cls != 'fire' &&
                              cls != 'fire_smoke') {
                            return false;
                          }
                          if (_typeFilter == 'smoke' &&
                              cls != 'smoke' &&
                              cls != 'fire_smoke') {
                            return false;
                          }
                        }
                        if (q.isNotEmpty) {
                          final hay =
                              '${inc.title} ${inc.locationName ?? ''} ${inc.id} ${inc.description ?? ''}'
                                  .toLowerCase();
                          if (!hay.contains(q)) return false;
                        }
                        final isUnread = !readIds.contains(inc.id) &&
                            inc.status == 'new';
                        if (_unreadOnly && !isUnread) return false;
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return IosSurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            vertical: 42,
                            horizontal: 24,
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen
                                      .withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.bell_slash_fill,
                                  size: 24,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                all.isEmpty
                                    ? 'No Alerts Recorded'
                                    : 'No Matching Alerts',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                all.isEmpty
                                    ? 'New wildfire detections and simulations will appear here.'
                                    : 'Try clearing your search, type, status, or severity filter.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (all.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    _searchCtrl.clear();
                                    _searchQuery = '';
                                    _typeFilter = 'all';
                                    _statusFilter = 'all';
                                    _severityFilter = 'all';
                                    _unreadOnly = false;
                                  }),
                                  child: const Text('Reset Filters'),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      // Group by date: TODAY, YESTERDAY, EARLIER
                      final grouped = <String, List<Incident>>{};
                      for (final inc in filtered) {
                        final g = _dateGroupLabel(inc.createdAt);
                        grouped.putIfAbsent(g, () => []).add(inc);
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 6,
                                top: 4,
                              ),
                              child: Text(
                                '${entry.key} (${entry.value.length})',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            IosSurfaceCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i < entry.value.length;
                                      i++) ...[
                                    _IosAlertRow(
                                      incident: entry.value[i],
                                      isUnread:
                                          !readIds.contains(entry.value[i].id) &&
                                              entry.value[i].status == 'new',
                                      onToggleRead: () {
                                        HapticFeedback.selectionClick();
                                        ref
                                            .read(
                                                readIncidentsProvider.notifier)
                                            .toggleRead(entry.value[i].id);
                                      },
                                      onDelete: () => _confirmDeleteIncident(
                                        entry.value[i],
                                      ),
                                      onTap: () {
                                        ref
                                            .read(
                                                readIncidentsProvider.notifier)
                                            .markRead(entry.value[i].id);
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(
                                            builder: (_) => IncidentScreen(
                                              incident: entry.value[i],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    if (i < entry.value.length - 1)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 56),
                                        child: Divider(height: 1),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      );
                    },
                    loading: () => const Column(
                      children: [
                        IosSkeletonCard(height: 92),
                        SizedBox(height: 12),
                        IosSkeletonCard(height: 92),
                      ],
                    ),
                    error: (e, _) => IosSurfaceCard(
                      child: Column(
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_triangle_fill,
                            color: AppColors.dangerRed,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load alerts: $e',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => refreshAllFireWatchData(ref),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterCapsule extends StatelessWidget {
  const _FilterCapsule({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.20)
              : AppColors.secondaryBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.65)
                : AppColors.cardBorder,
            width: 0.7,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _IosAlertRow extends StatelessWidget {
  const _IosAlertRow({
    required this.incident,
    required this.isUnread,
    required this.onToggleRead,
    required this.onDelete,
    required this.onTap,
  });

  final Incident incident;
  final bool isUnread;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sevColor = AppColors.forSeverity(incident.severity);
    final isSmoke = (incident.classification ?? '').toLowerCase() == 'smoke';

    return IosPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Threat Color Indicator & Icon
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSmoke
                        ? CupertinoIcons.smoke_fill
                        : CupertinoIcons.flame_fill,
                    color: sevColor,
                    size: 19,
                  ),
                ),
                if (isUnread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 1.8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          incident.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeOrShortTime(incident.createdAt),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${incident.locationName ?? "Sector"} · ${incident.lat.toStringAsFixed(4)}° N, ${incident.lon.toStringAsFixed(4)}° E',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      IosStatusPill(
                        label: AppColors.severityLabel(incident.severity),
                        color: sevColor,
                      ),
                      IosStatusPill(
                        label: AppColors.statusLabel(incident.status)
                            .toUpperCase(),
                        color: incident.isActive
                            ? AppColors.primaryGreen
                            : AppColors.textSecondary,
                      ),
                      if (incident.confidence != null)
                        IosStatusPill(
                          label:
                              '${(incident.confidence! * 100).toStringAsFixed(0)}%',
                          color: AppColors.primaryAccent,
                        ),
                      if (incident.isDemo)
                        const IosStatusPill(
                          label: 'DEMO',
                          color: AppColors.warningOrange,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(4),
                  minimumSize: Size.zero,
                  onPressed: onToggleRead,
                  child: Icon(
                    isUnread
                        ? CupertinoIcons.circle_fill
                        : CupertinoIcons.checkmark_circle,
                    size: isUnread ? 10 : 17,
                    color: isUnread
                        ? AppColors.primaryGreen
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                CupertinoButton(
                  padding: const EdgeInsets.all(4),
                  minimumSize: Size.zero,
                  onPressed: onDelete,
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
