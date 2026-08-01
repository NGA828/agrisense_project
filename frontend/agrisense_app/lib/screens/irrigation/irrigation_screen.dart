import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';

/// Farmer irrigation dashboard (Phase F, innovation #2).
///
/// Lists the farmer's soil-moisture sensors with a live, crop-aware irrigation
/// recommendation (moisture + trend + local rain probability + thresholds) and
/// lets the farmer register a new sensor and refresh advice.
class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _sensors = [];
  final Map<int, Map<String, dynamic>> _advice = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sensors = await _api.getMySensors();
      final advices = <int, Map<String, dynamic>>{};
      for (final s in sensors) {
        final id = s['id'] as int?;
        if (id == null) continue;
        if (s['sensor_type'] != 'soil_moisture') continue;
        try {
          advices[id] = await _api.getIrrigationAdvice(id);
        } catch (_) {
          advices[id] = {'recommendation': 'unavailable'};
        }
      }
      if (mounted) {
        setState(() {
          _sensors = sensors;
          _advice.addAll(advices);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    final advices = <int, Map<String, dynamic>>{};
    for (final s in _sensors) {
      final id = s['id'] as int?;
      if (id == null || s['sensor_type'] != 'soil_moisture') continue;
      try {
        advices[id] = await _api.getIrrigationAdvice(id);
      } catch (_) {
        advices[id] = {'recommendation': 'unavailable'};
      }
    }
    if (mounted) setState(() => _advice.addAll(advices));
  }

  Future<void> _addSensor() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _AddSensorDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _api.registerSensor(
        deviceId: result['device_id']!,
        sensorType: 'soil_moisture',
        name: result['name'] ?? '',
        crop: result['crop'] ?? '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sensor registered. Readings will appear here.'),
            backgroundColor: AppTheme.primary),
      );
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to register: $e'),
            backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'Irrigation',
              subtitle: user?.fullName ?? 'Your field sensors',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _isLoading ? null : _refreshAll,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _buildContent(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSensor,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add sensor',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildContent() {
    final soil = _sensors.where((s) => s['sensor_type'] == 'soil_moisture').toList();

    if (_sensors.isEmpty) {
      return const _EmptyState(
        icon: Icons.water_drop_outlined,
        message: 'No sensors yet.\nTap "Add sensor" to register a soil-moisture '
            'sensor for your field.',
      );
    }

    if (soil.isEmpty) {
      return const _EmptyState(
        icon: Icons.sensors_off_rounded,
        message: 'Register a soil-moisture sensor to get irrigation advice.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Soil-moisture sensors', style: FarmerTheme.sectionTitle()),
        const SizedBox(height: 12),
        ...soil.map((s) => _sensorCard(s)),
      ],
    );
  }

  Widget _sensorCard(dynamic sensor) {
    final id = sensor['id'] as int? ?? 0;
    final advice = _advice[id];
    final recommendation = advice?['recommendation'] ?? 'unavailable';
    final name = (sensor['name'] as String? ?? '').isNotEmpty
        ? sensor['name']
        : sensor['device_id'];
    final crop = (sensor['crop'] as String? ?? '').isNotEmpty
        ? sensor['crop']
        : advice?['crop']?.toString();

    final (icon, color, bg) = switch (recommendation) {
      'irrigate_now' => (Icons.water_drop_rounded, AppTheme.error, const Color(0xFFFFEBEE)),
      'delay_rain' => (Icons.umbrella_rounded, AppTheme.info, const Color(0xFFE3F2FD)),
      'monitor' => (Icons.visibility_rounded, AppTheme.warning, const Color(0xFFFFF3E0)),
      'adequate' => (Icons.check_circle_rounded, AppTheme.success, const Color(0xFFE8F5E9)),
      _ => (Icons.sensors_off_rounded, Colors.grey, Colors.grey.shade100),
    };

    final moisture = advice?['moisture'] as num?;
    final rain = advice?['rain_probability'] as num?;
    final threshold = advice?['threshold'] as Map<String, dynamic>?;
    final dry = (threshold?['dry'] as num?)?.toDouble();
    final adviceText = advice?['advice']?.toString() ?? 'No advice available.';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: bg,
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name?.toString() ?? 'Sensor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      '${crop?.toString() ?? 'General crop'} · ${_label(recommendation)}',
                      style: GoogleFonts.poppins(
                          color: color, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (moisture != null)
                Text('${moisture}%',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            ],
          ),
          if (moisture != null && dry != null) ...[
            const SizedBox(height: 12),
            LinearPercentIndicator(
              percent: (moisture / 100).clamp(0.0, 1.0),
              lineHeight: 8,
              barColor: color,
              backgroundColor: Colors.grey.shade200,
              animateFromLastPercent: true,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Dry below $dry%',
                    style: GoogleFonts.poppins(
                        color: Colors.grey.shade600, fontSize: 11)),
                const Spacer(),
                if (rain != null)
                  Text('Rain $rain%',
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(adviceText,
              style: GoogleFonts.poppins(
                  color: Colors.grey.shade700, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  String _label(String recommendation) {
    switch (recommendation) {
      case 'irrigate_now':
        return 'Irrigate now';
      case 'delay_rain':
        return 'Rain expected';
      case 'monitor':
        return 'Monitor';
      case 'adequate':
        return 'Adequate';
      default:
        return 'No data';
    }
  }
}

class _AddSensorDialog extends StatefulWidget {
  const _AddSensorDialog();

  @override
  State<_AddSensorDialog> createState() => _AddSensorDialogState();
}

class _AddSensorDialogState extends State<_AddSensorDialog> {
  final _deviceCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _crop = 'Tomato';

  static const _crops = ['Tomato', 'Maize', 'Cassava', 'Pepper', 'Cocoa'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Register soil sensor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deviceCtrl,
              decoration: const InputDecoration(
                  labelText: 'Device ID', hintText: 'e.g. SENS-001'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Sensor name (optional)', hintText: 'e.g. Field A'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _crop,
              decoration: const InputDecoration(labelText: 'Crop'),
              items: _crops
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _crop = v ?? 'Tomato'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final id = _deviceCtrl.text.trim();
            if (id.isEmpty) return;
            Navigator.pop(context, {
              'device_id': id,
              'name': _nameCtrl.text.trim(),
              'crop': _crop,
            });
          },
          child: const Text('Register'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppTheme.error)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600, fontSize: 13, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
