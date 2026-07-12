import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:pki/pki.dart';

import '../services/mesh_controller.dart';

enum _CalView { day, week, month }

/// Multi-scope calendars with day / week / month views + 24h time log.
class CalendarScreen extends StatefulWidget {
  final MeshController mesh;

  const CalendarScreen({super.key, required this.mesh});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  MeshController get mesh => widget.mesh;

  late DateTime _day;
  CalendarScope? _filter;
  _CalView _view = _CalView.day;
  bool _promptChecked = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptTimeLog());
  }

  DateTime get _weekStart {
    // Monday-based week.
    final wd = _day.weekday; // 1=Mon … 7=Sun
    return DateTime(_day.year, _day.month, _day.day)
        .subtract(Duration(days: wd - 1));
  }

  List<CalendarEvent> _eventsForLocalDay(DateTime localDay) {
    final utc = DateTime.utc(localDay.year, localDay.month, localDay.day);
    return mesh.calendars.forDay(utc, scope: _filter);
  }

  Future<void> _maybePromptTimeLog() async {
    if (_promptChecked || !mounted) return;
    _promptChecked = true;
    if (!mesh.shouldPromptTimeLog) return;
    final hour = mesh.timeLog.latestUnloggedHour() ?? DateTime.now().hour;
    await _logHourDialog(DateTime.now(), hour);
  }

  void _shift(int delta) {
    setState(() {
      switch (_view) {
        case _CalView.day:
          _day = _day.add(Duration(days: delta));
        case _CalView.week:
          _day = _day.add(Duration(days: 7 * delta));
        case _CalView.month:
          _day = DateTime(_day.year, _day.month + delta, 1);
      }
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    }
  }

  String _fmtTime(CalendarEvent e) {
    if (e.allDay) return 'All day';
    final local = e.start.toLocal();
    final end = e.end.toLocal();
    String t(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${t(local)}–${t(end)}';
  }

  String _header() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const short = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    switch (_view) {
      case _CalView.day:
        return '${short[_day.weekday - 1]}, ${months[_day.month - 1]} ${_day.day}';
      case _CalView.week:
        final end = _weekStart.add(const Duration(days: 6));
        return '${months[_weekStart.month - 1]} ${_weekStart.day} – '
            '${months[end.month - 1]} ${end.day}';
      case _CalView.month:
        return '${months[_day.month - 1]} ${_day.year}';
    }
  }

  IconData _scopeIcon(CalendarScope s) => switch (s) {
        CalendarScope.individual => Icons.person_outline,
        CalendarScope.family => Icons.family_restroom,
        CalendarScope.group => Icons.groups_outlined,
        CalendarScope.organization => Icons.apartment_outlined,
      };

  Color _scopeColor(BuildContext context, CalendarScope s) {
    final scheme = Theme.of(context).colorScheme;
    return switch (s) {
      CalendarScope.individual => scheme.primary,
      CalendarScope.family => scheme.tertiary,
      CalendarScope.group => scheme.secondary,
      CalendarScope.organization => scheme.error,
    };
  }

  Future<void> _compose({CalendarEvent? existing, DateTime? at}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _EventEditor(
          mesh: mesh,
          initialDay: at ?? _day,
          existing: existing,
          onSaved: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _logHourDialog(DateTime localDay, int hour) async {
    final existing = mesh.timeLog.slot(localDay, hour);
    final activityCtrl =
        TextEditingController(text: existing?.activity ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String? preset = existing?.activity;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('Log ${TimeLogEntry.formatHour(hour)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      TimeLogEntry.dayKeyOf(localDay),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final p in TimeLogPresets.common)
                          ChoiceChip(
                            label: Text(p),
                            selected: preset == p,
                            onSelected: (_) {
                              setLocal(() {
                                preset = p;
                                activityCtrl.text = p;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: activityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Activity',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: () {
                      mesh.clearTimeSlot(localDay, hour);
                      Navigator.pop(context, false);
                    },
                    child: const Text('Clear'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Later'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true && activityCtrl.text.trim().isNotEmpty) {
      mesh.logTimeSlot(
        localDay: localDay,
        hour: hour,
        activity: activityCtrl.text,
        notes: notesCtrl.text,
      );
      if (mounted) setState(() {});
    }
    activityCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _confirmDelete(CalendarEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove event?'),
        content: Text('“${e.title}” will be removed for this calendar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await mesh.deleteCalendarEvent(e.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = _day.year == DateTime.now().year &&
        _day.month == DateTime.now().month &&
        _day.day == DateTime.now().day;
    final filled = mesh.timeLog.filledCount(_day);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(),
        icon: const Icon(Icons.add),
        label: const Text('Event'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        children: [
          // View switcher
          SegmentedButton<_CalView>(
            segments: const [
              ButtonSegment(
                value: _CalView.day,
                label: Text('Day'),
                icon: Icon(Icons.view_day_outlined, size: 18),
              ),
              ButtonSegment(
                value: _CalView.week,
                label: Text('Week'),
                icon: Icon(Icons.view_week_outlined, size: 18),
              ),
              ButtonSegment(
                value: _CalView.month,
                label: Text('Month'),
                icon: Icon(Icons.calendar_view_month_outlined, size: 18),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: 8),
          // Navigator
          Row(
            children: [
              IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: InkWell(
                  onTap: _pickDay,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          _header(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          isToday && _view == _CalView.day
                              ? 'Today · time log $filled/24'
                              : 'Tap date to jump',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
              if (!isToday)
                TextButton(
                  onPressed: () {
                    final n = DateTime.now();
                    setState(
                      () => _day = DateTime(n.year, n.month, n.day),
                    );
                  },
                  child: const Text('Today'),
                ),
            ],
          ),
          // Scope filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final s in CalendarScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Icon(_scopeIcon(s), size: 18),
                      label: Text(s.shortLabel),
                      selected: _filter == s,
                      onSelected: (_) => setState(() => _filter = s),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Sync + time log actions
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (mesh.groups.all.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    for (final g in mesh.groups.all) {
                      await mesh.resyncGroupCalendars(g.id);
                    }
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Group calendars re-synced')),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync groups'),
                ),
              if (mesh.trustStore.organizationList.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    for (final o in mesh.trustStore.organizationList) {
                      await mesh.resyncOrganizationCalendars(o.id);
                    }
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Org calendars re-synced')),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync orgs'),
                ),
              TextButton.icon(
                onPressed: () => _logHourDialog(
                  DateTime.now(),
                  DateTime.now().hour,
                ),
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: Text(
                  mesh.shouldPromptTimeLog
                      ? 'Log this hour'
                      : 'Time log',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          switch (_view) {
            _CalView.day => _buildDayView(scheme),
            _CalView.week => _buildWeekView(scheme),
            _CalView.month => _buildMonthView(scheme),
          },
        ],
      ),
    );
  }

  Widget _buildDayView(ColorScheme scheme) {
    final events = _eventsForLocalDay(_day);
    final byHour = <int, List<CalendarEvent>>{};
    for (final e in events) {
      if (e.allDay) {
        byHour.putIfAbsent(-1, () => []).add(e);
        continue;
      }
      final h = e.start.toLocal().hour;
      byHour.putIfAbsent(h, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (byHour[-1] != null) ...[
          Text(
            'All day',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          for (final e in byHour[-1]!) _eventTile(context, e),
          const SizedBox(height: 8),
        ],
        Text(
          '24-hour schedule',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        for (var h = 0; h < 24; h++)
          _hourRow(
            scheme: scheme,
            hour: h,
            events: byHour[h] ?? const [],
            log: mesh.timeLog.slot(_day, h),
          ),
      ],
    );
  }

  Widget _hourRow({
    required ColorScheme scheme,
    required int hour,
    required List<CalendarEvent> events,
    required TimeLogEntry? log,
  }) {
    final now = DateTime.now();
    final isNow = _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day &&
        hour == now.hour;

    return Material(
      color: isNow
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : (hour.isEven ? scheme.surfaceContainerLowest : null),
      child: InkWell(
        onTap: () => _logHourDialog(_day, hour),
        onLongPress: () => _compose(
          at: DateTime(_day.year, _day.month, _day.day, hour),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  TimeLogEntry.formatHour(hour),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (log != null)
                      Text(
                        '⏱ ${log.activity}'
                        '${log.notes != null && log.notes!.isNotEmpty ? ' · ${log.notes}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Text(
                        isNow ? 'Tap to log this hour' : '—',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    for (final e in events)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _miniEventChip(e),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniEventChip(CalendarEvent e) {
    final color = _scopeColor(context, e.scope);
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _compose(existing: e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${_fmtTime(e)} · ${e.title}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekView(ColorScheme scheme) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final start = _weekStart;

    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = start.add(Duration(days: i));
              final events = _eventsForLocalDay(d);
              final filled = mesh.timeLog.filledCount(d);
              final isSel = d.year == _day.year &&
                  d.month == _day.month &&
                  d.day == _day.day;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isSel
                    ? scheme.primaryContainer.withValues(alpha: 0.4)
                    : null,
                child: InkWell(
                  onTap: () => setState(() {
                    _day = d;
                    _view = _CalView.day;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${labels[i]} ${d.month}/${d.day}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              '$filled/24 logged · ${events.length} event(s)',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (events.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'No events',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.outline,
                              ),
                            ),
                          )
                        else
                          for (final e in events.take(4))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '• ${_fmtTime(e)} ${e.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMonthView(ColorScheme scheme) {
    final first = DateTime(_day.year, _day.month, 1);
    final daysInMonth = DateTime(_day.year, _day.month + 1, 0).day;
    final startPad = first.weekday - 1; // Mon=0
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.85,
          ),
          itemCount: startPad + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startPad) return const SizedBox.shrink();
            final dayNum = index - startPad + 1;
            final d = DateTime(_day.year, _day.month, dayNum);
            final events = _eventsForLocalDay(d);
            final logCount = mesh.timeLog.filledCount(d);
            final isSel = dayNum == _day.day;
            final isToday = d.year == DateTime.now().year &&
                d.month == DateTime.now().month &&
                d.day == DateTime.now().day;

            return Material(
              color: isSel
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _day = d;
                  _view = _CalView.day;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontWeight: isToday || isSel
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday ? scheme.primary : null,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (events.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < events.length && i < 3; i++)
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: _scopeColor(context, events[i].scope),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      if (logCount > 0)
                        Text(
                          '$logCount',
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Events on ${_day.month}/${_day.day}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ..._eventsForLocalDay(_day).map((e) => _eventTile(context, e)),
        if (_eventsForLocalDay(_day).isEmpty)
          const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('No events this day'),
          ),
      ],
    );
  }

  Widget _eventTile(BuildContext context, CalendarEvent e) {
    final color = _scopeColor(context, e.scope);
    final scopeLabel = mesh.calendarScopeLabel(e);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(_scopeIcon(e.scope), color: color, size: 20),
        ),
        title: Text(e.title),
        subtitle: Text(
          '${_fmtTime(e)} · $scopeLabel'
          '${e.location != null && e.location!.isNotEmpty ? ' · ${e.location}' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                await _compose(existing: e);
              case 'delete':
                await _confirmDelete(e);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
        onTap: () => _compose(existing: e),
      ),
    );
  }
}

class _EventEditor extends StatefulWidget {
  final MeshController mesh;
  final DateTime initialDay;
  final CalendarEvent? existing;
  final VoidCallback onSaved;

  const _EventEditor({
    required this.mesh,
    required this.initialDay,
    this.existing,
    required this.onSaved,
  });

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _loc;
  late CalendarScope _scope;
  String _scopeId = '';
  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  bool _saving = false;
  String? _error;

  MeshController get mesh => widget.mesh;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _loc = TextEditingController(text: e?.location ?? '');
    _scope = e?.scope ?? CalendarScope.individual;
    _scopeId = e?.scopeId ?? '';
    _allDay = e?.allDay ?? false;
    if (e != null) {
      _start = e.start.toLocal();
      _end = e.end.toLocal();
    } else {
      final d = widget.initialDay;
      _start = DateTime(d.year, d.month, d.day, d.hour, d.minute);
      if (_start.hour == 0 && _start.minute == 0) {
        final now = DateTime.now();
        _start = DateTime(d.year, d.month, d.day, now.hour + 1, 0);
      }
      _end = _start.add(const Duration(hours: 1));
    }
    if (_scope == CalendarScope.group &&
        _scopeId.isEmpty &&
        mesh.groups.all.isNotEmpty) {
      _scopeId = mesh.groups.all.first.id;
    }
    if (_scope == CalendarScope.organization &&
        _scopeId.isEmpty &&
        mesh.trustStore.organizationList.isNotEmpty) {
      _scopeId = mesh.trustStore.organizationList.first.id;
    }
    if (_scope == CalendarScope.family && _scopeId.isEmpty) {
      _scopeId = 'family';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _loc.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    TimeOfDay? t;
    if (!_allDay) {
      t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_start),
      );
      if (t == null || !mounted) return;
    }
    setState(() {
      _start = DateTime(
        d.year,
        d.month,
        d.day,
        _allDay ? 0 : (t?.hour ?? _start.hour),
        _allDay ? 0 : (t?.minute ?? _start.minute),
      );
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    TimeOfDay? t;
    if (!_allDay) {
      t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_end),
      );
      if (t == null || !mounted) return;
    }
    setState(() {
      _end = DateTime(
        d.year,
        d.month,
        d.day,
        _allDay ? 0 : (t?.hour ?? _end.hour),
        _allDay ? 0 : (t?.minute ?? _end.minute),
      );
    });
  }

  String _fmt(DateTime d) {
    if (_allDay) {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await mesh.upsertCalendarEvent(
        id: widget.existing?.id,
        title: _title.text,
        description: _desc.text,
        location: _loc.text,
        start: _start,
        end: _end,
        allDay: _allDay,
        scope: _scope,
        scopeId: _scopeId,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final groups = mesh.groups.all;
    final orgs = mesh.trustStore.organizationList;
    final peers = mesh.visiblePeers;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'New event' : 'Edit event',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Text('Calendar', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in CalendarScope.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _scope == s,
                    onSelected: (_) {
                      setState(() {
                        _scope = s;
                        if (s == CalendarScope.family) {
                          _scopeId = 'family';
                        } else if (s == CalendarScope.group &&
                            groups.isNotEmpty) {
                          _scopeId = groups.first.id;
                        } else if (s == CalendarScope.organization &&
                            orgs.isNotEmpty) {
                          _scopeId = orgs.first.id;
                        } else if (s == CalendarScope.individual) {
                          _scopeId = '';
                        }
                      });
                    },
                  ),
              ],
            ),
            if (_scope == CalendarScope.individual) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _scopeId.isEmpty ? '' : _scopeId,
                decoration: const InputDecoration(
                  labelText: 'Share with (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Just me (private)'),
                  ),
                  for (final p in peers)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.displayName.isNotEmpty ? p.displayName : p.id,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _scopeId = v ?? ''),
              ),
            ],
            if (_scope == CalendarScope.group) ...[
              const SizedBox(height: 8),
              if (groups.isEmpty)
                const Text(
                  'Create a group first (Peers / Chat).',
                  style: TextStyle(fontSize: 12),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: groups.any((g) => g.id == _scopeId)
                      ? _scopeId
                      : groups.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Group',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final g in groups)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setState(() => _scopeId = v ?? ''),
                ),
            ],
            if (_scope == CalendarScope.organization) ...[
              const SizedBox(height: 8),
              if (orgs.isEmpty)
                const Text(
                  'Trust or create an organization in Credentials first.',
                  style: TextStyle(fontSize: 12),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: orgs.any((o) => o.id == _scopeId)
                      ? _scopeId
                      : orgs.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Organization',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final Organization o in orgs)
                      DropdownMenuItem(value: o.id, child: Text(o.name)),
                  ],
                  onChanged: (v) => setState(() => _scopeId = v ?? ''),
                ),
            ],
            if (_scope == CalendarScope.family) ...[
              const SizedBox(height: 8),
              Text(
                mesh.familySafety.isGuardian || mesh.familySafety.isWard
                    ? 'Shared with co-parents and kids on the family safety graph.'
                    : 'Tip: set up Family safety so events sync to Mom/Dad/kids.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts'),
              subtitle: Text(_fmt(_start)),
              trailing: const Icon(Icons.schedule),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends'),
              subtitle: Text(_fmt(_end)),
              trailing: const Icon(Icons.schedule),
              onTap: _pickEnd,
            ),
            TextField(
              controller: _loc,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 2,
              maxLines: 4,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
