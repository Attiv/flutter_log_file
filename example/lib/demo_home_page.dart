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
    _messageController = TextEditingController(text: '这是一条 VLog 示例消息');
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
              'Android · Windows 日志体验台',
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
              label: const Text('查看日志'),
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
      title: '输出配置',
      subtitle: '修改后点击应用，会创建新的 VLog session。',
      child: Column(
        children: [
          _ConfigSwitch(
            key: const Key('console-enabled-switch'),
            title: '终端输出',
            subtitle: '将日志输出到调试终端',
            value: _consoleEnabled,
            onChanged: (value) => setState(() => _consoleEnabled = value),
          ),
          _ConfigSwitch(
            key: const Key('file-enabled-switch'),
            title: '文件输出',
            subtitle: '写入应用私有 Support/logs 目录',
            value: _fileEnabled,
            onChanged: (value) => setState(() => _fileEnabled = value),
          ),
          _ConfigSwitch(
            key: const Key('show-tag-switch'),
            title: '显示 Tag',
            subtitle: 'Tag 仍然可以不传',
            value: _showTag,
            onChanged: (value) => setState(() => _showTag = value),
          ),
          _ConfigSwitch(
            key: const Key('pretty-json-switch'),
            title: '格式化 JSON',
            subtitle: '默认关闭，打开后多行展示',
            value: _prettyJson,
            onChanged: (value) => setState(() => _prettyJson = value),
          ),
          _ConfigSwitch(
            key: const Key('split-by-day-switch'),
            title: '按天生成文件',
            subtitle: '跨过零点后自动切换文件',
            value: _splitByDay,
            onChanged: (value) => setState(() => _splitByDay = value),
          ),
          _ConfigSwitch(
            key: const Key('console-colors-switch'),
            title: '终端颜色',
            subtitle: '仅影响终端，不写入日志文件',
            value: _consoleUseColors,
            onChanged: (value) => setState(() => _consoleUseColors = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('prefix-field'),
            controller: _prefixController,
            decoration: const InputDecoration(
              labelText: '日志文件前缀',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LogLevel>(
            key: const Key('minimum-level-field'),
            value: _minimumLevel,
            decoration: const InputDecoration(
              labelText: '最低日志等级',
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
              label: Text(_applying ? '正在应用…' : '应用配置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaygroundCard() {
    return _SectionCard(
      icon: Icons.terminal_rounded,
      title: '日志实验台',
      subtitle: '每次点击都会写入当前启用的输出端。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('message-field'),
            controller: _messageController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '日志内容',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('tag-field'),
            controller: _tagController,
            decoration: const InputDecoration(
              labelText: 'Tag（可留空）',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Text('日志等级', style: Theme.of(context).textTheme.titleSmall),
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
          Text('结构化与异常', style: Theme.of(context).textTheme.titleSmall),
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
                label: const Text('对象'),
              ),
              OutlinedButton.icon(
                key: const Key('log-exception'),
                onPressed: _writeError,
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('异常与堆栈'),
              ),
              OutlinedButton.icon(
                key: const Key('log-burst'),
                onPressed: _writeBurst,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('生成 200 条'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _TipBox(
            text:
                '快速定位建议：为业务模块使用稳定 Tag，并在消息中加入订单号、设备号或请求 ID。然后在查看页组合 Tag、等级、日期和关键词搜索。',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _openViewer,
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('打开日志查看器'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('flush-logs'),
                tooltip: '立即刷新日志',
                onPressed: _flushLogs,
                icon: const Icon(Icons.sync_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('clear-logs'),
                tooltip: '清空日志',
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
    _showMessage('${_levelLabel(level)} 日志已发送');
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
          'authorization': '默认不会脱敏，需显式配置 redactedKeys',
        },
      },
      tag: _tag ?? 'Network',
      fields: const {'source': 'demo-json'},
    );
    _showMessage('JSON 示例已发送');
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
    _showMessage('toJson() 与自定义编码器对象已发送');
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
    _showMessage('异常、字段和 StackTrace 已发送');
  }

  void _writeBurst() {
    for (var index = 1; index <= 200; index++) {
      VLog.d(
        '批量日志 $index / 200',
        tag: 'Burst',
        fields: {'batch': 'DEMO-BATCH', 'index': index},
      );
    }
    _showMessage('已生成 200 条日志，可体验懒加载与搜索');
  }

  Future<void> _applyConfiguration() async {
    final prefix = _prefixController.text.trim();
    if (prefix.isEmpty) {
      _showMessage('日志文件前缀不能为空', error: true);
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
        _showMessage('配置已应用，并创建了新的 VLog session');
      }
    } catch (error) {
      if (mounted) _showMessage('应用配置失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _flushLogs() async {
    await VLog.flush();
    if (mounted) _showMessage('日志已刷新到输出端');
  }

  Future<void> _confirmClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部日志？'),
        content: const Text('此操作会删除当前 VLog 目录中的全部日志文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VLog.clearLogs();
    if (mounted) {
      setState(() {});
      _showMessage('日志文件已清空');
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
      title: '运行状态',
      subtitle: initialized ? 'VLog 已初始化' : 'VLog 尚未初始化',
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
            label: '文件前缀',
            value: filePrefix ?? '—',
          ),
          const SizedBox(height: 10),
          _StatusRow(
            label: '日志目录',
            value: directory ?? '文件输出未启用',
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
