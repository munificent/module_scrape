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

    for (var entry in Directory(packageDir).listSync(recursive: true)) {
      if (entry is! File) continue;

      if (!entry.path.endsWith('.dart')) continue;

      // For unknown reasons, some READMEs have a ".dart" extension. They
      // aren't Dart files.
      if (entry.path.endsWith('README.dart')) continue;

      // TODO: This assumes all files are libraries. Need to handle parts.
      var relative = p.relative(entry.path, from: packageDir);
      graph._parseFile(entry as File, relative);
    }

    return graph;
  }

  /// The name of the package being analyzed.
  final String _packageName;

  final Map<String, GraphNode> libraries = {};

  ImportGraph._(this._packageName);

  void _addLibrary(String library) {
    libraries[library] = GraphNode();
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
  /// package using its internal imports and exports as edges.
  ///
  /// See: https://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm
  List<List<String>> connectedComponents() {
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
      for (var other in node.imports) {
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
      var node = libraries[lib];
      print('$lib:');
      var imports = node.imports.toList()..sort();
      for (var i in imports) {
        print('- $i');
      }
    }
  }

  void _parseFile(File file, String shortPath) {
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
      node = parser.parseDirectives(startToken);
    } catch (error) {
      print('Got exception parsing $shortPath:\n$error');
      return;
    }

    // Don't process files with syntax errors.
    if (errorListener.hadError) return;

    _addLibrary(shortPath);
    node.accept(_ImportVisitor(this, shortPath));
  }
}

class GraphNode {
  /// List of imports of libraries not in this package.
  final List<String> externalImports = [];

  /// List of relative paths for imports of libraries in this package.
  final List<String> imports = [];
}

class _ImportVisitor extends RecursiveAstVisitor<void> {
  final ImportGraph _graph;
  final String _path;

  _ImportVisitor(this._graph, this._path);

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
