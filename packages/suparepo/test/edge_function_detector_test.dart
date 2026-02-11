import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:suparepo/src/edge_function_detector.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String basePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('edge_test_');
    basePath = tempDir.path;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('EdgeFunctionDetector', () {
    test('index.tsがあるディレクトリを検出', () async {
      // Setup: create two function directories with index.ts
      final func1Dir = Directory(p.join(basePath, 'send-email'));
      await func1Dir.create();
      await File(p.join(func1Dir.path, 'index.ts')).create();

      final func2Dir =
          Directory(p.join(basePath, 'process-payment'));
      await func2Dir.create();
      await File(p.join(func2Dir.path, 'index.ts')).create();

      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, hasLength(2));
      expect(
        functions.map((f) => f.name),
        containsAll(['process-payment', 'send-email']),
      );
    });

    test('_で始まるディレクトリは除外', () async {
      final funcDir = Directory(p.join(basePath, 'my-func'));
      await funcDir.create();
      await File(p.join(funcDir.path, 'index.ts')).create();

      final sharedDir = Directory(p.join(basePath, '_shared'));
      await sharedDir.create();
      await File(p.join(sharedDir.path, 'index.ts')).create();

      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'my-func');
    });

    test('.で始まるディレクトリは除外', () async {
      final funcDir = Directory(p.join(basePath, 'my-func'));
      await funcDir.create();
      await File(p.join(funcDir.path, 'index.ts')).create();

      final hiddenDir = Directory(p.join(basePath, '.hidden'));
      await hiddenDir.create();
      await File(p.join(hiddenDir.path, 'index.ts')).create();

      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'my-func');
    });

    test('index.tsがないディレクトリは無視', () async {
      final funcDir = Directory(p.join(basePath, 'valid-func'));
      await funcDir.create();
      await File(p.join(funcDir.path, 'index.ts')).create();

      final emptyDir = Directory(p.join(basePath, 'empty-func'));
      await emptyDir.create();
      // No index.ts

      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'valid-func');
    });

    test('ディレクトリが存在しない場合は空リスト', () async {
      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(
        p.join(basePath, 'nonexistent'),
      );

      expect(functions, isEmpty);
    });

    test('空のディレクトリの場合は空リスト', () async {
      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, isEmpty);
    });

    test('結果はname順にソートされる', () async {
      for (final name in ['charlie', 'alpha', 'bravo']) {
        final dir = Directory(p.join(basePath, name));
        await dir.create();
        await File(p.join(dir.path, 'index.ts')).create();
      }

      final detector = EdgeFunctionDetector();
      final functions = await detector.detect(basePath);

      expect(functions, hasLength(3));
      expect(
        functions.map((f) => f.name).toList(),
        ['alpha', 'bravo', 'charlie'],
      );
    });
  });
}
