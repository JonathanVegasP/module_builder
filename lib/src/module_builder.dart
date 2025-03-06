import 'dart:async';

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
    final imports = <Directive>[];
    final buffer = StringBuffer();

    var isConst = 'const ';

    await for (final input in buildStep.findAssets(_allFiles)) {
      if (!await buildStep.resolver.isLibrary(input)) continue;

      final reader = LibraryReader(await buildStep.resolver.libraryFor(input));

      final cls = reader.classes;

      var isLibraryEmpty = true;

      for(final el in cls) {
        if(!superModuleChecker.isAssignableFrom(el)) continue;

        if (el.unnamedConstructor == null) {
          throw UnsupportedError(
            '${el.name}: Cannot use Module without an unnamed constructor',
          );
        }

        if (el.unnamedConstructor!.isConst != true) {
          isConst = '';
        }

        buffer.write('${el.name}(),');

        if(isLibraryEmpty) isLibraryEmpty = false;
      }

      if (isLibraryEmpty) continue;

      imports.add(
        Directive(
          (b) =>
              b
                ..type = DirectiveType.import
                ..url =
                    'package:${input.package}/${input.pathSegments.skip(1).join('/')}',
        ),
      );
    }

    final library = Library(
      (b) =>
          b
            ..directives.addAll(imports)
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
                                  'await Future.wait($isConst[$buffer].map((el) => el.init()))',
                                ),
                        ),
                      ),
              ),
            ),
    );

    final output = AssetId(
      buildStep.inputId.package,
      join('lib', 'config', 'modules', 'modules.dart'),
    );

    return buildStep.writeAsString(
      output,
      DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format('${library.accept(DartEmitter.scoped())}'),
    );
  }
}
