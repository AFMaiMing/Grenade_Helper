import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'bootstrap/main_window_bootstrap.dart';
import 'bootstrap/overlay_process_bootstrap.dart';

export 'bootstrap/app_globals.dart'
    show
        clearOverlayActiveMap,
        globalHotkeyService,
        globalIsar,
        globalOverlayServer,
        globalSettingsService,
        globalWindowService,
        sendOverlayCommand,
        setOverlayActiveMap;
export 'bootstrap/main_app_host.dart' show MainApp;
export 'bootstrap/overlay_process_bootstrap.dart'
    show OverlayWindowApp, OverlayWindowAppState;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    fvp.registerWith(options: {
      'platforms': ['windows'],
    });
  }

  if (args.contains('--overlay')) {
    await runOverlayProcess(args);
    return;
  }

  await runMainWindow();
}
