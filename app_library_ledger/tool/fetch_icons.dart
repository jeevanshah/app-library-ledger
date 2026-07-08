/// Standalone CLI tool — NOT part of the app.
/// Run with:  dart run tool/fetch_icons.dart
///
/// Reads assets/catalog.json, downloads favicons for every entry that has
/// a non-empty "domain" field to assets/service_icons/<id>.png (128px).
/// Skips files that already exist. Prints a summary at the end.
import 'dart:convert';
import 'dart:io';

const _catalogPath = 'assets/catalog.json';
const _outDir = 'assets/service_icons';
const _fetchUrl = 'https://www.google.com/s2/favicons?domain={domain}&sz=128';

Future<void> main() async {
  final catalogFile = File(_catalogPath);
  if (!catalogFile.existsSync()) {
    stderr.writeln('❌ $_catalogPath not found — run from the project root');
    exit(1);
  }

  final raw = await catalogFile.readAsString();
  final List<dynamic> entries = jsonDecode(raw);

  final outDir = Directory(_outDir);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  int fetched = 0, skipped = 0, failed = 0;

  for (final e in entries) {
    final id = e['id'] as String?;
    final domain = e['domain'] as String?;
    if (id == null || domain == null || domain.isEmpty) continue;

    final outFile = File('$_outDir/$id.png');
    if (outFile.existsSync()) {
      skipped++;
      continue;
    }

    final url = _fetchUrl.replaceFirst('{domain}', domain);
    stdout.write('Fetching $id ($domain)... ');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        await outFile.writeAsBytes(bytes);
        fetched++;
        stdout.writeln('✅');
      } else {
        failed++;
        stdout.writeln('❌ HTTP ${response.statusCode}');
      }
    } catch (ex) {
      failed++;
      stdout.writeln('❌ $ex');
    }
  }

  stdout.writeln('');
  stdout.writeln('═══════════════════════════════════');
  stdout.writeln(
    'Summary: $fetched fetched, $skipped skipped (already exist), $failed failed',
  );
}
