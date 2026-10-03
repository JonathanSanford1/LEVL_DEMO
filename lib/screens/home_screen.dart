import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../health_service.dart';
import '../models.dart';
import '../widgets/charts.dart';
import 'privacy_screen.dart';

enum _Status { loading, healthConnectMissing, notConnected, connected }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _connectedKey = 'connected';
  static const _nameKey = 'userName';

  final _service = HealthService();
  _Status _status = _Status.loading;
  DashboardData? _data;
  String _userName = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Refresh whenever the app returns to the foreground (e.g. after the
  /// person installs Health Connect or changes permissions in Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_status == _Status.connected) {
      _refresh();
    } else if (_status == _Status.healthConnectMissing) {
      _start();
    }
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    final available = await _service.isAvailable();
    if (!mounted) return;
    setState(() => _userName = prefs.getString(_nameKey) ?? '');

    if (!available) {
      setState(() => _status = _Status.healthConnectMissing);
    } else if (prefs.getBool(_connectedKey) ?? false) {
      setState(() => _status = _Status.connected);
      await _refresh();
    } else {
      setState(() => _status = _Status.notConnected);
    }
  }

  Future<void> _connect() async {
    bool granted = false;
    try {
      granted = await _service.connect();
    } catch (e) {
      _showMessage('Could not connect: $e');
      return;
    }
    if (!granted) {
      _showMessage('Permission was not granted. Tap Connect to try again.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectedKey, true);
    if (!mounted) return;
    setState(() => _status = _Status.connected);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await _service.loadDashboard();
      if (mounted) setState(() => _data = data);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeTest(Future<bool> Function() write, String label) async {
    try {
      final ok = await write();
      _showMessage(ok ? '$label saved to ${_service.platformName}' : 'Could not save $label');
      if (ok) await _refresh();
    } catch (e) {
      _showMessage('Could not save $label: $e');
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _userName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Shown at the top of your dashboard'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
    if (mounted) setState(() => _userName = name);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_userName.isEmpty ? 'Health Demo' : "$_userName's Health"),
        actions: [
          IconButton(
            tooltip: 'Set your name',
            icon: const Icon(Icons.person_outline),
            onPressed: _editName,
          ),
          IconButton(
            tooltip: 'Privacy policy',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            ),
          ),
        ],
      ),
      body: switch (_status) {
        _Status.loading => const Center(child: CircularProgressIndicator()),
        _Status.healthConnectMissing => _messageView(
            icon: Icons.download_outlined,
            title: 'Health Connect is required',
            body: 'This phone needs the Health Connect app to share health data.',
            buttonLabel: 'Install Health Connect',
            onPressed: _service.installHealthConnect,
          ),
        _Status.notConnected => _messageView(
            icon: _service.isIOS ? Icons.apple : Icons.android,
            title: 'Connect to ${_service.platformName}',
            body: 'This app reads your steps, active energy, heart rate, sleep and '
                'workouts from ${_service.platformDetail}. Your data never leaves this phone.',
            buttonLabel: 'Connect',
            onPressed: _connect,
          ),
        _Status.connected => _dashboard(),
      },
    );
  }

  Widget _messageView({
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() {
    final data = _data;
    if (data == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sourceCard(data),
          _todayCard(data),
          _stepsCard(data),
          _heartRateCard(data),
          _sleepCard(data),
          _workoutsCard(data),
          _testCard(),
          if (data.errors.isNotEmpty) _errorsCard(data),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sourceCard(DashboardData data) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(_service.isIOS ? Icons.apple : Icons.android, size: 36),
        title: Text('Connected to ${_service.platformName}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${_service.platformDetail}\n'
            'Last synced ${DateFormat.jm().format(data.fetchedAt)}'),
        isThreeLine: true,
        trailing: _busy
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
      ),
    );
  }

  Widget _todayCard(DashboardData data) {
    final latest = data.latestHeartRate;
    return _section(
      'Today',
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          _metric(Icons.directions_walk, Colors.green, 'Steps',
              NumberFormat.decimalPattern().format(data.stepsToday.round())),
          _metric(Icons.local_fire_department, Colors.orange, 'Active energy',
              '${data.activeKcalToday.round()} kcal'),
          _metric(Icons.favorite, Colors.red, 'Latest heart rate',
              latest == null ? '—' : '${latest.bpm.round()} bpm'),
          _metric(Icons.favorite_border, Colors.pink, 'Resting heart rate',
              data.restingHeartRate == null ? '—' : '${data.restingHeartRate!.round()} bpm'),
        ],
      ),
    );
  }

  Widget _stepsCard(DashboardData data) {
    return _section(
      'Steps, last 7 days',
      data.weeklySteps.isEmpty
          ? _empty('No step data')
          : WeeklyBarChart(days: data.weeklySteps, color: Colors.green),
    );
  }

  Widget _heartRateCard(DashboardData data) {
    final points = data.heartRateToday;
    if (points.isEmpty) return _section('Heart rate today', _empty('No heart rate samples today'));

    final bpms = points.map((p) => p.bpm);
    final minBpm = bpms.reduce((a, b) => a < b ? a : b);
    final maxBpm = bpms.reduce((a, b) => a > b ? a : b);
    final avg = bpms.reduce((a, b) => a + b) / points.length;
    return _section(
      'Heart rate today',
      Column(
        children: [
          HeartRateLine(points: points, color: Colors.red),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Min', '${minBpm.round()}'),
              _stat('Avg', '${avg.round()}'),
              _stat('Max', '${maxBpm.round()}'),
              _stat('Samples', '${points.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sleepCard(DashboardData data) {
    final sleep = data.lastNightSleep;
    if (sleep == null) return _section("Last night's sleep", _empty('No sleep data for last night'));
    return _section(
      "Last night's sleep",
      Column(
        children: [
          _row('Total asleep', _formatHours(sleep.totalAsleepHours), bold: true),
          for (final stage in sleep.stages) _row(stage.name, _formatHours(stage.hours)),
          _row('Source', sleep.source),
        ],
      ),
    );
  }

  Widget _workoutsCard(DashboardData data) {
    if (data.workouts.isEmpty) return _section('Workouts, last 30 days', _empty('No workouts'));
    return _section(
      'Workouts, last 30 days',
      Column(
        children: [
          for (final w in data.workouts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_workoutDetail(w)),
              trailing: Text(DateFormat.MMMd().add_jm().format(w.start),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _testCard() {
    return _section(
      'Test the connection',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'These save real samples into ${_service.platformName}. '
            'They appear there with this app listed as the source.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.favorite),
            label: const Text('Write test heart rate'),
            onPressed: () => _writeTest(_service.writeTestHeartRate, 'Heart rate sample'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.directions_walk),
            label: const Text('Write 500 test steps'),
            onPressed: () => _writeTest(_service.writeTestSteps, 'Steps'),
          ),
        ],
      ),
    );
  }

  Widget _errorsCard(DashboardData data) {
    return _section(
      'Problems reading some data',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in data.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Small building blocks
  // ---------------------------------------------------------------------------

  Widget _section(String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, Color color, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                Text(value,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _empty(String text) => Text(text, style: TextStyle(color: Theme.of(context).hintColor));

  String _formatHours(double hours) {
    final minutes = (hours * 60).round();
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _workoutDetail(WorkoutItem w) {
    final parts = ['${w.minutes.round()} min'];
    if (w.kcal != null && w.kcal! > 0) parts.add('${w.kcal!.round()} kcal');
    if (w.miles != null && w.miles! > 0) parts.add('${w.miles!.toStringAsFixed(2)} mi');
    return parts.join(' · ');
  }
}
