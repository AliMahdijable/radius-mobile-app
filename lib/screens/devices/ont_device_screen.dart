import 'package:flutter/material.dart';

import '../../core/services/huawei_ont_service.dart';
import '../../models/ont_info.dart';

class OntDeviceArgs {
  final String host;
  final String user;
  final String pass;

  const OntDeviceArgs({required this.host, required this.user, required this.pass});
}

class OntDeviceScreen extends StatefulWidget {
  final OntDeviceArgs args;

  const OntDeviceScreen({super.key, required this.args});

  @override
  State<OntDeviceScreen> createState() => _OntDeviceScreenState();
}

class _OntDeviceScreenState extends State<OntDeviceScreen> {
  OntOpticalInfo? _optical;
  List<OntVoipLine> _voip = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final session = await HuaweiOntService.login(
      widget.args.host, widget.args.user, widget.args.pass,
    );
    if (session == null) {
      if (mounted) setState(() { _loading = false; _error = 'فشل تسجيل الدخول'; });
      return;
    }
    final results = await Future.wait([
      HuaweiOntService.fetchOptical(session),
      HuaweiOntService.fetchVoip(session),
    ]);
    if (mounted) {
      setState(() {
        _optical = results[0] as OntOpticalInfo?;
        _voip = (results[1] as List<OntVoipLine>?) ?? const [];
        _loading = false;
        if (_optical == null) _error = 'تعذّر جلب بيانات الضوء';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ONT — ${widget.args.host}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OpticalCard(info: _optical!),
                      if (_voip.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _VoipCard(lines: _voip),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _OpticalCard extends StatelessWidget {
  final OntOpticalInfo info;

  const _OpticalCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'معلومات الضوء (Optical)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _table(context),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context) {
    final rows = [
      _Row(
        label: 'قوة الإرسال',
        sublabel: 'TX Power',
        value: '${info.txPower} dBm',
        ref: '0.5 ~ 5.0 dBm',
        ok: info.txOk,
      ),
      _Row(
        label: 'قوة الاستقبال',
        sublabel: 'RX Power',
        value: '${info.rxPower} dBm',
        ref: '-27 ~ -3 dBm',
        ok: info.rxOk,
      ),
      _Row(
        label: 'الجهد الكهربائي',
        sublabel: 'Voltage',
        value: '${info.voltage} mV',
        ref: '3100 ~ 3500 mV',
        ok: info.voltageOk,
      ),
      _Row(
        label: 'تيار الإرسال',
        sublabel: 'Bias Current',
        value: '${info.bias} mA',
        ref: '0 ~ 90 mA',
        ok: info.biasOk,
      ),
      _Row(
        label: 'درجة الحرارة',
        sublabel: 'Temperature',
        value: '${info.temperature} °C',
        ref: '-10 ~ 85 °C',
        ok: info.tempOk,
      ),
    ];

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2.5),
        3: IntrinsicColumnWidth(),
      },
      children: [
        _headerRow(context),
        ...rows.map((r) => _dataRow(context, r)),
      ],
    );
  }

  TableRow _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      children: [
        _cell(Text('البند', style: style), bottom: 6),
        _cell(Text('القيمة الحالية', style: style), bottom: 6),
        _cell(Text('النطاق المرجعي', style: style), bottom: 6),
        _cell(Text('الحالة', style: style), bottom: 6),
      ],
    );
  }

  TableRow _dataRow(BuildContext context, _Row r) {
    final cs = Theme.of(context).colorScheme;
    const goodColor = Color(0xFF2E7D32);
    final badColor = cs.error;

    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4))),
      ),
      children: [
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              Text(r.sublabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
            ],
          ),
        ),
        _cell(
          Text(
            r.value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: r.ok ? goodColor : badColor,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
          ),
        ),
        _cell(
          Text(r.ref,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
        ),
        _cell(
          Icon(
            r.ok ? Icons.check_circle : Icons.cancel,
            color: r.ok ? goodColor : badColor,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _cell(Widget child, {double bottom = 10}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: bottom / 2 + 4, horizontal: 4),
      child: child,
    );
  }
}

class _Row {
  final String label;
  final String sublabel;
  final String value;
  final String ref;
  final bool ok;

  const _Row({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.ref,
    required this.ok,
  });
}

class _VoipCard extends StatelessWidget {
  final List<OntVoipLine> lines;

  const _VoipCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'خطوط الهاتف (VoIP)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...lines.map((l) => _lineRow(context, l)),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(BuildContext context, OntVoipLine line) {
    const goodColor = Color(0xFF2E7D32);
    final cs = Theme.of(context).colorScheme;

    final Color statusColor;
    final IconData statusIcon;
    if (line.isUp) {
      statusColor = goodColor;
      statusIcon = Icons.check_circle;
    } else if (line.isDisabled) {
      statusColor = cs.onSurfaceVariant;
      statusIcon = Icons.remove_circle_outline;
    } else {
      statusColor = cs.error;
      statusIcon = Icons.cancel;
    }

    final errorLabel = line.registerError.isEmpty ? '' : line.registerError.replaceAll('_', ' ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'خط ${line.index}${line.directoryNumber.isNotEmpty ? "  —  ${line.directoryNumber}" : ""}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${line.status}  ·  ${line.callState}${errorLabel.isNotEmpty ? "  ·  $errorLabel" : ""}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
