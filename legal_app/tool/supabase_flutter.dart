// Runs `flutter run` / `flutter build ...` with the Supabase public
// configuration compiled in, validated by the app's own rules.
//
//   cd legal_app
//   dart run tool/supabase_flutter.dart run [-d <device>]
//   dart run tool/supabase_flutter.dart build apk --release
//   dart run tool/supabase_flutter.dart build appbundle --release
//   dart run tool/supabase_flutter.dart build ipa --release
//   dart run tool/supabase_flutter.dart build web --release
//
// Values: environment variables SUPABASE_URL / SUPABASE_ANON_KEY /
// SUPABASE_AUTH_REDIRECT_URL first, then the git-ignored supabase.local.json,
// then (URL only) the connected project. The key is printed only redacted.
// Server-only variables are removed from the Flutter process environment.
import 'dart:convert';
import 'dart:io';

import 'package:legalserviceapp/config/supabase_client_config.dart';

const String defaultSupabaseUrl = 'https://qqfzbecwhewswkyxgebu.supabase.co';
const List<String> defineNames = <String>[
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_AUTH_REDIRECT_URL',
];
const List<String> serverOnlyVariables = <String>[
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_SECRET_KEY',
];

class ResolvedDefines {
  ResolvedDefines(this.values, this.sources);

  final Map<String, String> values;
  final Map<String, String> sources;
}

/// Environment first, then [localFile] (a `--dart-define-from-file` JSON).
ResolvedDefines resolveDefines(
  Map<String, String> environment,
  File localFile,
) {
  Map<String, dynamic> fromFile = const <String, dynamic>{};
  if (localFile.existsSync()) {
    final decoded = jsonDecode(localFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        '${SupabaseClientConfig.localDefinesFile} must be a JSON object.',
      );
    }
    fromFile = decoded;
  }
  final values = <String, String>{};
  final sources = <String, String>{};
  for (final name in defineNames) {
    final env = (environment[name] ?? '').trim();
    final file =
        fromFile[name] is String ? (fromFile[name] as String).trim() : '';
    if (env.isNotEmpty) {
      values[name] = env;
      sources[name] = 'environment';
    } else if (file.isNotEmpty) {
      values[name] = file;
      sources[name] = SupabaseClientConfig.localDefinesFile;
    } else if (name == 'SUPABASE_URL') {
      values[name] = defaultSupabaseUrl;
      sources[name] = 'default';
    } else {
      values[name] = '';
      sources[name] = 'unset';
    }
  }
  return ResolvedDefines(values, sources);
}

List<String> flutterArguments(
  List<String> cliArgs,
  Map<String, String> values,
) {
  final defines = <String>[
    for (final name in defineNames)
      if (values[name]!.isNotEmpty) '--dart-define=$name=${values[name]}',
  ];
  // `flutter run ...` / `flutter build <target> ...`: defines go after the
  // subcommand (and build target) so they apply to that exact build.
  final insertAt = cliArgs.first == 'build' && cliArgs.length > 1 ? 2 : 1;
  return <String>[
    ...cliArgs.take(insertAt),
    ...defines,
    ...cliArgs.skip(insertAt),
  ];
}

Map<String, String> flutterEnvironment(Map<String, String> environment) =>
    Map<String, String>.of(environment)
      ..removeWhere((name, _) => serverOnlyVariables.contains(name));

String printable(List<String> args, String key) => <String>[
  'flutter',
  for (final arg in args)
    key.isNotEmpty && arg.contains(key)
        ? arg.replaceAll(key, SupabaseClientConfig.redactKey(key))
        : arg,
].join(' ');

/// Returns the process exit code. Injectable for tests.
Future<int> runTool(
  List<String> cliArgs, {
  Map<String, String>? environment,
  Directory? packageDir,
  String flutterExecutable = 'flutter',
  StringSink? out,
  StringSink? err,
}) async {
  final env = environment ?? Platform.environment;
  final dir = packageDir ?? Directory.current;
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  if (cliArgs.isEmpty || !const {'run', 'build'}.contains(cliArgs.first)) {
    stderrSink.writeln(
      'Usage: dart run tool/supabase_flutter.dart <run|build <target>> [flutter args]',
    );
    return 64;
  }
  if (cliArgs.any(
    (arg) =>
        arg.startsWith('--dart-define-from-file') ||
        defineNames.any((name) => arg.contains('--dart-define=$name=')),
  )) {
    stderrSink.writeln(
      'Do not pass Supabase defines to this helper; it supplies them. '
      'Use the environment or ${SupabaseClientConfig.localDefinesFile}.',
    );
    return 64;
  }
  if (!File('${dir.path}/pubspec.yaml').existsSync()) {
    stderrSink.writeln('Run this helper from the legal_app directory.');
    return 64;
  }

  final ResolvedDefines resolved;
  try {
    resolved = resolveDefines(
      env,
      File('${dir.path}/${SupabaseClientConfig.localDefinesFile}'),
    );
  } on FormatException catch (error) {
    stderrSink.writeln(
      'Invalid ${SupabaseClientConfig.localDefinesFile}: ${error.message}',
    );
    return 1;
  }

  final key = resolved.values['SUPABASE_ANON_KEY']!;
  final config = SupabaseClientConfig.resolve(
    url: resolved.values['SUPABASE_URL']!,
    anonKey: key,
  );
  if (!config.isValid) {
    stderrSink.writeln('Supabase configuration is invalid:');
    for (final issue in config.issueDescriptions) {
      stderrSink.writeln('  - $issue');
    }
    stderrSink.writeln(
      'Set SUPABASE_ANON_KEY in the environment or copy '
      'supabase.local.example.json to ${SupabaseClientConfig.localDefinesFile} '
      'and paste the PUBLIC key. Never use a secret/service-role key.',
    );
    return 1;
  }

  final args = flutterArguments(cliArgs, resolved.values);
  stdoutSink
    ..writeln('Supabase configuration:')
    ..writeln(
      '  SUPABASE_URL      ${config.url} [${resolved.sources['SUPABASE_URL']}]',
    )
    ..writeln(
      '  SUPABASE_ANON_KEY ${config.redactedKey} [${resolved.sources['SUPABASE_ANON_KEY']}]',
    )
    ..writeln(
      '  SUPABASE_AUTH_REDIRECT_URL '
      '${resolved.values['SUPABASE_AUTH_REDIRECT_URL']!.isEmpty ? '(not set)' : resolved.values['SUPABASE_AUTH_REDIRECT_URL']} '
      '[${resolved.sources['SUPABASE_AUTH_REDIRECT_URL']}]',
    )
    ..writeln('> ${printable(args, key)}');

  try {
    final process = await Process.start(
      flutterExecutable,
      args,
      workingDirectory: dir.path,
      environment: flutterEnvironment(env),
      includeParentEnvironment: false,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    return await process.exitCode;
  } on ProcessException catch (error) {
    stderrSink.writeln('Could not start flutter: ${error.message}');
    return 1;
  }
}

Future<void> main(List<String> args) async {
  exitCode = await runTool(args);
}
