import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../config/theme.dart';

/// Root app shown when the compiled Supabase configuration is invalid.
///
/// It is rendered instead of the login flow so no auth or data request is
/// attempted with incomplete credentials. Retrying cannot help because Dart
/// defines are fixed at compile time, so the screen explains how to rebuild.
class SupabaseConfigErrorApp extends StatelessWidget {
  const SupabaseConfigErrorApp({super.key, required this.config});

  final SupabaseConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legal Services Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SupabaseConfigErrorScreen(config: config),
    );
  }
}

class SupabaseConfigErrorScreen extends StatelessWidget {
  const SupabaseConfigErrorScreen({super.key, required this.config});

  final SupabaseConfig config;

  static const String _commands =
      '# Uses SUPABASE_ANON_KEY from the shell or admin_panel/supabase.local.json\n'
      'node scripts/run_web.mjs\n'
      '\n'
      '# Or pass the defines directly\n'
      '${SupabaseConfig.runCommandHint}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      key: const Key('supabase-config-error'),
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.settings_suggest_outlined,
                          color: AppTheme.warning,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Supabase is not configured for this build',
                            style: textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    for (final issue in config.issueDescriptions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.error_outline,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(issue)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Compiled values — URL: '
                      '${config.url.isEmpty ? '(missing)' : config.url} · '
                      'key: ${config.redactedKey}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('How to fix', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SelectableText(
                        _commands,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Dart defines are compiled into the app. Stop and relaunch '
                      '`flutter run` (hot restart does not apply new defines) or '
                      'rebuild the web bundle. Shell and hosting environment '
                      'variables are not read at runtime. Use only the public '
                      'anon/publishable key — never a secret or service-role key.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
