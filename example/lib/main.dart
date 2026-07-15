import 'package:flutter/material.dart';
import 'package:flutter_log_file/flutter_log_file.dart';

import 'demo_app.dart';
import 'demo_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  VLog.registerEncoder<DemoOrder>(encodeDemoOrder);
  await VLog.init(
    LogConfig(
      consoleEnabled: true,
      fileEnabled: true,
      showTag: true,
      prettyJson: false,
      filePrefix: 'vlog_demo',
      splitByDay: true,
    ),
  );
  VLog.i('VLog demo started', tag: 'Bootstrap');

  runApp(const DemoApp());
}
