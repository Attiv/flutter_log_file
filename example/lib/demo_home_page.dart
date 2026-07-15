import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_log_file/flutter_log_file.dart';

import 'demo_models.dart';

final class DemoHomePage extends StatefulWidget {
  const DemoHomePage({
    super.key,
    this.testDirectoryPath,
    this.configurationApplier,
    this.viewerRepository,
  });

  /// Keeps widget tests independent from platform directory plugins.
  final String? testDirectoryPath;

  /// Allows widget tests to inspect configuration without invoking plugins.
  final Future<void> Function(LogConfig config)? configurationApplier;

  /// Allows hosts or tests to provide a custom log file repository.
  final LogViewerRepository? viewerRepository;

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

final class _DemoHomePageState extends State<DemoHomePage>
    with WidgetsBindingObserver {
  late final TextEditingController _messageController;
  late final TextEditingController _tagController;
  late final TextEditingController _prefixController;

  bool _consoleEnabled = true;
  bool _fileEnabled = true;
  bool _showTag = true;
  bool _prettyJson = false;
  bool _splitByDay = true;
  bool _consoleUseColors = true;
  bool _applying = false;
  LogLevel _minimumLevel = LogLevel.verbose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final config = VLog.config;
    _consoleEnabled = config?.consoleEnabled ?? true;
    _fileEnabled = config?.fileEnabled ?? true;
    _showTag = config?.showTag ?? true;
    _prettyJson = config?.prettyJson ?? false;
    _splitByDay = config?.splitByDay ?? true;
    _consoleUseColors = config?.consoleUseColors ?? true;
    _minimumLevel = config?.minimumLevel ?? LogLevel.verbose;
    _messageController = TextEditingController(
      text: 'This is a VLog sample message',
    );
    _tagController = TextEditingController(text: 'Demo');
    _prefixController = TextEditingController(
      text: config?.filePrefix ?? 'vlog_demo',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(VLog.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _tagController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('demo-home-page'),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VLog Playground'),
            Text(
              'Android · Windows logging playground',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              key: const Key('open-viewer'),
              onPressed: _openViewer,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('View logs'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            final statusAndConfig = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusCard(
                  initialized: VLog.isInitialized,
                  directory: VLog.logDirectoryPath,
                  filePrefix: VLog.config?.filePrefix,
                ),
                const SizedBox(height: 16),
                _buildConfigCard(),
              ],
            );
            final playground = _buildPlaygroundCard();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 4, child: statusAndConfig),
                            const SizedBox(width: 16),
                            Expanded(flex: 6, child: playground),
                          ],
                        )
                      : Column(
                          children: [
                            statusAndConfig,
                            const SizedBox(height: 16),
                            playground,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return _SectionCard(
      icon: Icons.tune_rounded,
      title: 'Output configuration',
      subtitle: 'Applying changes creates a new VLog session.',
      child: Column(
        children: [
          _ConfigSwitch(
            key: const Key('console-enabled-switch'),
            title: 'Console output',
            subtitle: 'Print logs to the debug console',
            value: _consoleEnabled,
            onChanged: (value) => setState(() => _consoleEnabled = value),
          ),
          _ConfigSwitch(
            key: const Key('file-enabled-switch'),
            title: 'File output',
            subtitle: 'Write logs to the private Support/logs directory',
            value: _fileEnabled,
            onChanged: (value) => setState(() => _fileEnabled = value),
          ),
          _ConfigSwitch(
            key: const Key('show-tag-switch'),
            title: 'Show tag',
            subtitle: 'The tag remains optional for every log call',
            value: _showTag,
            onChanged: (value) => setState(() => _showTag = value),
          ),
          _ConfigSwitch(
            key: const Key('pretty-json-switch'),
            title: 'Pretty JSON',
            subtitle: 'Disabled by default; enabled output uses multiple lines',
            value: _prettyJson,
            onChanged: (value) => setState(() => _prettyJson = value),
          ),
          _ConfigSwitch(
            key: const Key('split-by-day-switch'),
            title: 'Split files by day',
            subtitle: 'Automatically switch files after midnight',
            value: _splitByDay,
            onChanged: (value) => setState(() => _splitByDay = value),
          ),
          _ConfigSwitch(
            key: const Key('console-colors-switch'),
            title: 'Console colors',
            subtitle: 'Affects the console only, never log files',
            value: _consoleUseColors,
            onChanged: (value) => setState(() => _consoleUseColors = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('prefix-field'),
            controller: _prefixController,
            decoration: const InputDecoration(
              labelText: 'Log file prefix',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LogLevel>(
            key: const Key('minimum-level-field'),
            value: _minimumLevel,
            decoration: const InputDecoration(
              labelText: 'Minimum log level',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
            items: LogLevel.values
                .map(
                  (level) => DropdownMenuItem(
                    value: level,
                    child: Text(_levelLabel(level)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _minimumLevel = value);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('apply-config'),
              onPressed: _applying ? null : _applyConfiguration,
              icon: _applying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(_applying ? 'Applying…' : 'Apply configuration'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaygroundCard() {
    return _SectionCard(
      icon: Icons.terminal_rounded,
      title: 'Log playground',
      subtitle: 'Each action writes to the currently enabled outputs.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('message-field'),
            controller: _messageController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Log message',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('tag-field'),
            controller: _tagController,
            decoration: const InputDecoration(
              labelText: 'Tag (optional)',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Text('Log levels', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LogLevel.values
                .map(
                  (level) => _LevelButton(
                    key: Key('log-${level.name}'),
                    level: level,
                    onPressed: () => _writeLevel(level),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          Text(
            'Structured data and errors',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('log-json'),
                onPressed: _writeJson,
                icon: const Icon(Icons.data_object_rounded),
                label: const Text('JSON'),
              ),
              OutlinedButton.icon(
                key: const Key('log-object'),
                onPressed: _writeObjects,
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('Objects'),
              ),
              OutlinedButton.icon(
                key: const Key('log-exception'),
                onPressed: _writeError,
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Error & stack trace'),
              ),
              OutlinedButton.icon(
                key: const Key('log-burst'),
                onPressed: _writeBurst,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Generate 200 logs'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _TipBox(
            text:
                'Quick location tip: use stable tags for each module and include an order ID, device ID, or request ID in the message. Combine tags, levels, dates, and keywords in the viewer.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _openViewer,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('Open log viewer'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('flush-logs'),
                tooltip: 'Flush logs now',
                onPressed: _flushLogs,
                icon: const Icon(Icons.sync_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('clear-logs'),
                tooltip: 'Clear logs',
                onPressed: _confirmClearLogs,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? get _tag {
    final value = _tagController.text.trim();
    return value.isEmpty ? null : value;
  }

  void _writeLevel(LogLevel level) {
    final message = _messageController.text.trim().isEmpty
        ? 'Empty demo message'
        : _messageController.text;
    switch (level) {
      case LogLevel.verbose:
        VLog.v(message, tag: _tag);
      case LogLevel.debug:
        VLog.d(message, tag: _tag);
      case LogLevel.info:
        VLog.i(message, tag: _tag);
      case LogLevel.warning:
        VLog.w(message, tag: _tag);
      case LogLevel.error:
        VLog.e(message, tag: _tag);
      case LogLevel.fatal:
        VLog.f(message, tag: _tag);
    }
    _showMessage('${_levelLabel(level)} log sent');
  }

  void _writeJson() {
    VLog.i(
      {
        'requestId': 'REQ-${DateTime.now().millisecondsSinceEpoch}',
        'endpoint': '/v1/orders',
        'retry': 2,
        'success': true,
        'payload': {
          'items': ['keyboard', 'mouse'],
          'authorization':
              'Redaction is disabled until redactedKeys is configured',
        },
      },
      tag: _tag ?? 'Network',
      fields: const {'source': 'demo-json'},
    );
    _showMessage('JSON sample sent');
  }

  void _writeObjects() {
    const user = DemoUser(
      id: 7,
      name: 'Ada',
      roles: ['admin', 'tester'],
      active: true,
    );
    const order = DemoOrder(
      id: 'ORDER-2026-001',
      amount: 128.50,
      state: DemoOrderState.paid,
    );
    VLog.i(user, tag: _tag ?? 'User');
    VLog.i(order, tag: _tag ?? 'Order');
    _showMessage('toJson() and custom encoder samples sent');
  }

  void _writeError() {
    final error = StateError('Demo API timeout after 3 retries');
    VLog.e(
      'Demo request failed',
      tag: _tag ?? 'API',
      error: error,
      stackTrace: StackTrace.current,
      fields: const {'requestId': 'REQ-DEMO-ERROR', 'retry': 3},
    );
    _showMessage('Error, fields, and stack trace sent');
  }

  void _writeBurst() {
    for (var index = 1; index <= 200; index++) {
      VLog.d(
        'Burst log $index / 200',
        tag: 'Burst',
        fields: {'batch': 'DEMO-BATCH', 'index': index},
      );
    }
    _showMessage('Generated 200 logs for lazy loading and search');
  }

  Future<void> _applyConfiguration() async {
    final prefix = _prefixController.text.trim();
    if (prefix.isEmpty) {
      _showMessage('The log file prefix cannot be empty', error: true);
      return;
    }
    setState(() => _applying = true);
    try {
      final config = LogConfig(
        consoleEnabled: _consoleEnabled,
        fileEnabled: _fileEnabled,
        minimumLevel: _minimumLevel,
        showTag: _showTag,
        prettyJson: _prettyJson,
        consoleUseColors: _consoleUseColors,
        directoryPath: widget.testDirectoryPath,
        filePrefix: prefix,
        splitByDay: _splitByDay,
        retentionDays: 30,
        maxFileSizeBytes: 50 * 1024 * 1024,
      );
      await (widget.configurationApplier ?? VLog.init)(config);
      VLog.i(
        'VLog configuration applied',
        tag: 'Configuration',
        fields: {
          'console': _consoleEnabled,
          'file': _fileEnabled,
          'prettyJson': _prettyJson,
          'splitByDay': _splitByDay,
        },
      );
      if (mounted) {
        setState(() {});
        _showMessage('Configuration applied. A new VLog session was created.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Failed to apply configuration: $error', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
    }
  }

  Future<void> _flushLogs() async {
    await VLog.flush();
    if (mounted) _showMessage('Logs flushed to all enabled outputs');
  }

  Future<void> _confirmClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all logs?'),
        content: const Text(
          'This deletes every log file in the current VLog directory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VLog.clearLogs();
    if (mounted) {
      setState(() {});
      _showMessage('Log files cleared');
    }
  }

  void _openViewer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VLogViewerPage(repository: widget.viewerRepository),
      ),
    );
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.initialized,
    required this.directory,
    required this.filePrefix,
  });

  final bool initialized;
  final String? directory;
  final String? filePrefix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.monitor_heart_outlined,
      title: 'Runtime status',
      subtitle: initialized ? 'VLog is initialized' : 'VLog is not initialized',
      trailing: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: initialized ? const Color(0xFF00A884) : colors.error,
          boxShadow: [
            BoxShadow(
              color: (initialized ? const Color(0xFF00A884) : colors.error)
                  .withValues(alpha: 0.35),
              blurRadius: 8,
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          _StatusRow(
            label: 'File prefix',
            value: filePrefix ?? '—',
          ),
          const SizedBox(height: 10),
          _StatusRow(
            label: 'Log directory',
            value: directory ?? 'File output is disabled',
            valueKey: const Key('status-directory'),
          ),
        ],
      ),
    );
  }
}

final class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child:
                      Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

final class _ConfigSwitch extends StatelessWidget {
  const _ConfigSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

final class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            key: valueKey,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

final class _LevelButton extends StatelessWidget {
  const _LevelButton({
    super.key,
    required this.level,
    required this.onPressed,
  });

  final LogLevel level;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level, Theme.of(context).brightness);
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
      onPressed: onPressed,
      child: Text(_levelLabel(level)),
    );
  }
}

final class _TipBox extends StatelessWidget {
  const _TipBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: colors.secondary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

String _levelLabel(LogLevel level) => switch (level) {
      LogLevel.verbose => 'Verbose',
      LogLevel.debug => 'Debug',
      LogLevel.info => 'Info',
      LogLevel.warning => 'Warning',
      LogLevel.error => 'Error',
      LogLevel.fatal => 'Fatal',
    };

Color _levelColor(LogLevel level, Brightness brightness) => switch (level) {
      LogLevel.verbose => brightness == Brightness.dark
          ? const Color(0xFFB8C2CC)
          : const Color(0xFF52606D),
      LogLevel.debug => const Color(0xFF5C7CFA),
      LogLevel.info => const Color(0xFF00A884),
      LogLevel.warning => const Color(0xFFF59F00),
      LogLevel.error => const Color(0xFFE03131),
      LogLevel.fatal => const Color(0xFF9C36B5),
    };
