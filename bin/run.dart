// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:module_scrape/src/import_graph.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  String package;
  String path;
  if (arguments.length == 1) {
    path = arguments[0];
    package = p.basename(path);

    // Strip off a version number if there is one.
    var dash = package.indexOf('-');
    if (dash != -1) {
      package = package.substring(0, dash);
    }
  } else if (arguments.length == 2) {
    package = arguments[0];
    path = arguments[1];
  } else {
    print('Usage: run.dart [package] <path>');
    exit(1);
  }

  var graph = ImportGraph.read(package, path);
  var components = graph.connectedComponents();
  for (var component in components) {
    print('- ${component.join(' ')}');
  }
}

/// Generate a PNG of the import graph using graphviz.
void generateGraphviz(ImportGraph graph) {
  String viz(String library) => '"${library.replaceAll('.dart', '')}"';

  var buffer = StringBuffer();
  buffer.writeln('strict digraph {');
  // buffer.writeln('  graph [overlap=false, sep="+1", outputorder=edgesfirst];');
  buffer.writeln('  node [label="", shape=point, width=0.2, height=0.2];');
  // buffer.writeln('  node [shape=rect];');
  buffer.writeln('  edge [len=0.1, color=gray, arrowsize=0.5];');

  var components = graph.connectedComponents();
  for (var i = 0; i < components.length; i++) {
    var component = components[i];
    if (component.length > 1) {
      buffer.writeln('  subgraph cluster_$i {');
    }

    for (var from in component) {
      var color = 'blue';
      if (from.startsWith('test/')) {
        color = 'green';
      } else if (from.startsWith('lib/src/')) {
        color = 'black';
      } else if (from.startsWith('lib/')) {
        color = 'red';
      }
      buffer.writeln('    ${viz(from)} [color=$color];');

      var node = graph.libraries[from];
      var imports = node.imports.toList()..sort();
      for (var to in imports) {
        buffer.writeln('    ${viz(from)} -> ${viz(to)};');
      }
    }

    if (component.length > 1) {
      buffer.writeln('  }');
    }
  }

  buffer.writeln('}');

  File('temp.dot').writeAsStringSync(buffer.toString());

  var result = Process.runSync('dot', ['-Tpng', 'temp.dot', '-o', 'temp.png']);
  if (result.exitCode != 0) {
    print(result.stdout);
    print(result.stderr);
  }
}
