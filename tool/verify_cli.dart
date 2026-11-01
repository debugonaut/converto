import 'dart:ffi';
import 'dart:io';

Future<void> main() async {
  Future<void> run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows && executable.endsWith('.bat'),
    );
    final code = await process.exitCode;
    if (code != 0)
      throw ProcessException(executable, args, 'CLI verification failed', code);
  }

  await run(Platform.resolvedExecutable, [
    'build',
    'cli',
    '--target',
    'bin/converto.dart',
    '--verbosity',
    'warning',
  ]);
  final arm64 = [
    Abi.macosArm64,
    Abi.linuxArm64,
    Abi.windowsArm64,
  ].contains(Abi.current());
  final binary = File(
    'build/cli/${Platform.operatingSystem}_${arm64 ? 'arm64' : 'x64'}/bundle/bin/converto${Platform.isWindows ? '.exe' : ''}',
  ).absolute;
  await File('build/cli-path.txt').writeAsString(binary.path);
  final scratch = await Directory.systemTemp.createTemp('converto-tests-');
  try {
    await run(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['test', '--no-pub'],
      environment: {
        'CONVERTO_TEST_BINARY': binary.path,
        'CONVERTO_OUTPUT_DIR': '${scratch.path}/output',
        'CONVERTO_DATA_DIR': '${scratch.path}/state',
        'CONVERTO_HISTORY': 'off',
      },
    );
  } finally {
    await scratch.delete(recursive: true);
  }
}
