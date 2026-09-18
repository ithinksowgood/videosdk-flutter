import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

Future<void> main() async {
  log('Setting up E2EE worker file...');

  final packageUri = Uri.parse('package:videosdk/assets/e2ee.worker.dart.js');
  final resolvedUri = await Isolate.resolvePackageUri(packageUri);

  if (resolvedUri == null) {
    log('ERROR: Could not resolve package asset path.');
    exit(1);
  }

  final sourcePath = resolvedUri.toFilePath();
  final destinationPath = '${Directory.current.path}/web/e2ee.worker.dart.js';

  try {
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      log('ERROR: Source file not found: $sourcePath');
      exit(1);
    }

    final webFolder = Directory('${Directory.current.path}/web');
    if (!webFolder.existsSync()) {
      webFolder.createSync(recursive: true);
    }

    sourceFile.copySync(destinationPath);
    log('E2EE worker file copied successfully to $destinationPath');
  } catch (e) {
    log('Error copying file: $e');
    exit(1);
  }
}
