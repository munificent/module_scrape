// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/scanner/reader.dart';
import 'package:analyzer/src/dart/scanner/scanner.dart';
import 'package:analyzer/src/generated/parser.dart';
import 'package:analyzer/src/string_source.dart';
import 'package:path/path.dart' as p;

import 'error_listener.dart';

class ImportGraph {
  static ImportGraph read(String packageName, String packageDir) {
    var graph = ImportGraph._(packageName);

    var parsedFiles = <String, AstNode>{};

    for (var entry in Directory(packageDir).listSync(recursive: true)) {
      if (entry is! File) continue;

      if (!entry.path.endsWith('.dart')) continue;

      // For unknown reasons, some READMEs have a ".dart" extension. They
      // aren't Dart files.
      if (entry.path.endsWith('README.dart')) continue;

      // TODO: This assumes all files are libraries. Need to handle parts.
      var relative = p.relative(entry.path, from: packageDir);
      var node = _parseFile(relative, entry as File);
      if (node != null) {
        parsedFiles[relative] = node;
        graph._addLibrary(relative);
      }
    }

    // Find all the classes.
    parsedFiles.forEach((shortPath, node) {
      node.accept(_ClassVisitor(graph, shortPath));
    });

    // Traverse the imports and uses.
    parsedFiles.forEach((shortPath, node) {
      graph._addLibrary(shortPath);
      node.accept(_UseVisitor(graph, shortPath));
    });

    return graph;
  }

  static AstNode _parseFile(String shortPath, File file) {
    var source = file.readAsStringSync();

    var errorListener = ErrorListener();
    var featureSet = FeatureSet.latestLanguageVersion();

    // Tokenize the source.
    var reader = CharSequenceReader(source);
    var stringSource = StringSource(source, file.path);
    var scanner = Scanner(stringSource, reader, errorListener);
    scanner.configureFeatures(
        featureSet: featureSet, featureSetForOverriding: featureSet);
    var startToken = scanner.tokenize();

    // Parse it.
    var parser = Parser(stringSource, errorListener, featureSet: featureSet);
    parser.enableOptionalNewAndConst = true;
    parser.enableSetLiterals = true;

    AstNode node;
    try {
      node = parser.parseCompilationUnit(startToken);
    } catch (error) {
      print('Got exception parsing $shortPath:\n$error');
      return null;
    }

    // Don't process files with syntax errors.
    if (errorListener.hadError) return null;

    return node;
  }

  /// The name of the package being analyzed.
  final String _packageName;

  /// The names of the classes defined by each library.
  // final Map<String, Set<String>> classes = {};
  /// Maps the name of each class to the library where it's defined.
  final Map<String, String> typeLibraries = {};

  final Map<String, GraphNode> libraries = {};

  ImportGraph._(this._packageName);

  void _addLibrary(String library) {
    libraries[library] = GraphNode();
  }

  void _addType(String library, String typeName) {
    // TODO: Collisions can happen because we don't actually resolve the names
    // and different libraries may define types with the same name. Just ignore
    // them.
    // if (classLibraries.containsKey(className)) {
    //   print('Class name collision in:\n'
    //       '- ${classLibraries[className]}\n'
    //       '- $library');
    // }

    typeLibraries[typeName] = library;
  }

  void _addClassUse(
      String fromLibrary, String fromClass, String use, String toClass) {
    var toLibrary = typeLibraries[toClass];
    // Ignore unknown classes. Assume they are from outside of the package.
    if (toLibrary == null) return;
    if (fromLibrary == toLibrary) return;

    switch (use) {
      case 'extend':
        libraries[fromLibrary].superclasses.add(toLibrary);
        break;
      case 'implement':
        libraries[fromLibrary].superinterfaces.add(toLibrary);
        break;
      case 'mixin':
        libraries[fromLibrary].mixins.add(toLibrary);
        break;
    }
  }

  void _addImport(String from, String to) {
    var node = libraries[from];
    if (to.startsWith('dart:')) {
      node.externalImports.add(to);
    } else if (to.startsWith('package:$_packageName/')) {
      node.imports.add(to.replaceAll('package:$_packageName/', 'lib/'));
    } else if (to.startsWith('package:')) {
      node.externalImports.add(to);
    } else {
      node.imports.add(p.url.normalize(p.url.join(p.url.dirname(from), to)));
    }
  }

  /// Calculates the strongly connected components of the libraries in this
  /// package using any edges that match [uses].
  ///
  /// See: https://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm
  List<List<String>> connectedComponents([Set<String> uses]) {
    var components = <List<String>>[];

    var index = 0;
    var nodeIndexes = <String, int>{};
    var lowIndexes = <String, int>{};
    var stack = <String>[];

    void connect(String library) {
      // Set the depth index for v to the smallest unused index.
      nodeIndexes[library] = index;
      lowIndexes[library] = index;
      index++;

      stack.add(library);

      var node = libraries[library];
      for (var other in node.references(uses)) {
        if (!libraries.containsKey(other)) {
          // Ignore imports of unknown libraries. This can happen with
          // generated code.
          // TODO: Do we need to worry about generated code in the analysis?
        } else if (!nodeIndexes.containsKey(other)) {
          // Successor w has not yet been visited; recurse on it.
          connect(other);
          lowIndexes[library] = min(lowIndexes[library], lowIndexes[other]);
        } else if (stack.contains(other)) {
          // Successor w is in stack S and hence in the current SCC.
          // If w is not on stack, then (v, w) is an edge pointing to an SCC
          // already found and must be ignored
          lowIndexes[library] = min(lowIndexes[library], nodeIndexes[other]);
        }
      }

      // If v is a root node, pop the stack and generate an SCC
      if (lowIndexes[library] == nodeIndexes[library]) {
        var component = <String>[];
        // Start a new strongly connected component.
        while (true) {
          var node = stack.removeLast();
          component.add(node);

          if (node == library) break;
        }

        components.add(component);
      }
    }

    for (var library in libraries.keys) {
      if (!nodeIndexes.containsKey(library)) {
        connect(library);
      }
    }

    return components;
  }

  void dump() {
    var libraryNames = libraries.keys.toList();
    libraryNames.sort();
    for (var lib in libraryNames) {
      print('$lib:');

      var node = libraries[lib];
      var references = node.references().toList()..sort();
      for (var other in references) {
        var uses = [
          if (node.imports.contains(other)) 'import',
          if (node.superclasses.contains(other)) 'extend',
          if (node.superinterfaces.contains(other)) 'implement',
          if (node.mixins.contains(other)) 'mixin',
        ];
        print('- [${uses.join(' ')}] $other');
      }
    }
  }
}

class GraphNode {
  /// List of imports of libraries not in this package.
  final Set<String> externalImports = {};

  /// Other libraries in this package imported or exported by this one.
  final Set<String> imports = {};

  /// Other libraries in this package containing classes that classes in this
  /// library extend.
  final Set<String> superclasses = {};

  /// Other libraries in this package containing classes that classes in this
  /// library implement.
  final Set<String> superinterfaces = {};

  /// Other libraries in this package containing classes that classes in this
  /// library mixin.
  final Set<String> mixins = {};

  /// Gets all of the libraries this library refers to according to [uses].
  Set<String> references([Set<String> uses]) {
    return {
      if (uses == null || uses.contains('import')) ...imports,
      if (uses == null || uses.contains('extend')) ...superclasses,
      if (uses == null || uses.contains('implement')) ...superinterfaces,
      if (uses == null || uses.contains('mixin')) ...mixins,
    };
  }
}

class _ClassVisitor extends RecursiveAstVisitor<void> {
  final ImportGraph _graph;
  final String _path;

  _ClassVisitor(this._graph, this._path);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _graph._addType(_path, node.name.name);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _graph._addType(_path, node.name.name);
    super.visitMixinDeclaration(node);
  }
}

class _UseVisitor extends RecursiveAstVisitor<void> {
  final ImportGraph _graph;
  final String _path;

  _UseVisitor(this._graph, this._path);

  // TODO: Constructor calls.

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    var name = node.name.name;

    var extendsClause = node.extendsClause;
    if (extendsClause != null) {
      _graph._addClassUse(
          _path, name, 'extend', extendsClause.superclass.name.name);
    }

    var implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (var interface in implementsClause.interfaces) {
        _graph._addClassUse(_path, name, 'implement', interface.name.name);
      }
    }

    var withClause = node.withClause;
    if (withClause != null) {
      for (var mixin in withClause.mixinTypes) {
        _graph._addClassUse(_path, name, 'mixin', mixin.name.name);
      }
    }

    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    var name = node.name.name;

    var implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (var interface in implementsClause.interfaces) {
        _graph._addClassUse(_path, name, 'implement', interface.name.name);
      }
    }

    super.visitMixinDeclaration(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    _graph._addImport(_path, node.uri.stringValue);
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _graph._addImport(_path, node.uri.stringValue);
    super.visitExportDirective(node);
  }
}
