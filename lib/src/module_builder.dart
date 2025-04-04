import 'dart:async';
import 'dart:ui';

import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:module/module.dart';
import 'package:path/path.dart';
import 'package:source_gen/source_gen.dart';

final class ModuleBuilder extends Builder {
  final _allFiles = Glob('**/**.dart');

  static const superModuleChecker = TypeChecker.fromRuntime(Module);

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['config/modules/modules.dart'],
  };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final importDirectives = <Directive>[];
    final moduleInstancesBuffer = StringBuffer();

    bool hasNonConstConstructor = false;

    final moduleFiles = await buildStep.findAssets(_allFiles).toList();
    final moduleProcessingFutures = <Future<void>>[];

    for (final asset in moduleFiles) {
      moduleProcessingFutures.add(
        _processModuleAsset(
          asset,
          buildStep,
          importDirectives,
          moduleInstancesBuffer,
          () {
            hasNonConstConstructor = true;
          },
        ),
      );
    }

    await Future.wait(moduleProcessingFutures);

    if (moduleInstancesBuffer.isEmpty) return;

    final generatedLibrary = Library(
      (b) =>
          b
            ..directives.addAll(importDirectives)
            ..body.add(
              Class(
                (b) =>
                    b
                      ..name = "Modules"
                      ..modifier = ClassModifier.final$
                      ..constructors.add(
                        Constructor(
                          (b) =>
                              b
                                ..name = "_"
                                ..constant = true,
                        ),
                      )
                      ..methods.add(
                        Method(
                          (b) =>
                              b
                                ..name = 'init'
                                ..static = true
                                ..lambda = true
                                ..returns = refer('Future<void>')
                                ..modifier = MethodModifier.async
                                ..body = Code(
                                  'await Future.wait(${hasNonConstConstructor ? '' : 'const '}[$moduleInstancesBuffer].map((module) => module.init()))',
                                ),
                        ),
                      ),
              ),
            ),
    );

    final outputFile = AssetId(
      buildStep.inputId.package,
      join('lib', 'config', 'modules', 'modules.dart'),
    );

    return buildStep.writeAsString(
      outputFile,
      DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format('${generatedLibrary.accept(DartEmitter.scoped())}'),
    );
  }

  static Future<void> _processModuleAsset(
    AssetId asset,
    BuildStep buildStep,
    List<Directive> importDirectives,
    StringBuffer moduleInstancesBuffer,
    VoidCallback markNonConst,
  ) async {
    if (!await buildStep.resolver.isLibrary(asset)) return;

    final libraryReader = LibraryReader(
      await buildStep.resolver.libraryFor(asset),
    );
    final moduleClasses = libraryReader.classes.where(
      superModuleChecker.isAssignableFrom,
    );

    if (moduleClasses.isEmpty) return;

    bool hasValidModules = false;

    for (final moduleClass in moduleClasses) {
      final unnamedConstructor = moduleClass.unnamedConstructor;
      if (unnamedConstructor == null) {
        throw UnsupportedError(
          '${moduleClass.name}: Cannot use Module without an unnamed constructor',
        );
      }

      if (!unnamedConstructor.isConst) {
        markNonConst();
      }

      moduleInstancesBuffer.write('${moduleClass.name}(),');
      hasValidModules = true;
    }

    if (!hasValidModules) return;

    importDirectives.add(
      Directive(
        (b) =>
            b
              ..type = DirectiveType.import
              ..url =
                  'package:${asset.package}/${asset.pathSegments.skip(1).join('/')}',
      ),
    );
  }
}
