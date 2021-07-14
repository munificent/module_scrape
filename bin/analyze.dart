// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:math';

import 'package:module_scrape/src/import_graph.dart';
import 'package:module_scrape/src/histogram.dart';
import 'package:module_scrape/src/yes_no.dart';

import 'package:path/path.dart' as p;

const percent = 100;

final allLibs = Histogram();
final publicLibs = Histogram();
final srcLibs = Histogram();
final testLibs = Histogram();
final otherLibs = Histogram();
final missingLibs = Histogram();
final componentCount = Histogram();
final multiLibComponentCount = Histogram();
final componentSizes = Histogram();

final questions = YesNo();

final random = Random(1234);

void main(List<String> arguments) {
  var directory = arguments[0];
  var packageDirs = Directory(directory)
      .listSync()
      .whereType<Directory>()
      .map((entry) => entry.path)
      .toList();
  packageDirs.sort();

  for (var packageDir in packageDirs) {
    if (random.nextInt(100) > percent) continue;

    var packageName = p.basename(packageDir);

    // Strip off a version number if there is one.
    var dash = packageName.indexOf('-');
    if (dash != -1) {
      packageName = packageName.substring(0, dash);
    }

    print(packageDir);
    var graph = ImportGraph.read(packageName, packageDir);

    var publicLibCount = 0;
    var srcLibCount = 0;
    var otherLibCount = 0;
    var testLibCount = 0;
    for (var library in graph.libraries.keys) {
      if (library.startsWith('lib/src/')) {
        srcLibCount++;
      } else if (library.startsWith('lib/')) {
        publicLibCount++;
      } else if (library.startsWith('test/')) {
        testLibCount++;
      } else {
        otherLibCount++;
      }
    }

    allLibs.add(graph.libraries.length);
    publicLibs.add(publicLibCount);
    srcLibs.add(srcLibCount);
    testLibs.add(testLibCount);
    otherLibs.add(otherLibCount);

    var components = graph.connectedComponents();
    componentCount.add(components.length);
    for (var component in components) {
      componentSizes.add(component.length);
    }

    // Note: missing is only populated after calling connectedComponents().
    missingLibs.add(graph.missing.length);

    var multiLibraryComponents =
        components.where((component) => component.length > 1).toList();
    multiLibComponentCount.add(multiLibraryComponents.length);

    questions.add('Has tests', testLibCount > 0);
    questions.add('Has src libs', srcLibCount > 0);
    questions.add('Has multi-lib component', multiLibraryComponents.isNotEmpty);
  }

  allLibs.printCounts('Libraries');
  publicLibs.printCounts('Public lib/ libraries');
  srcLibs.printCounts('Private lib/src/ libraries');
  testLibs.printCounts('Test test/ libraries');
  otherLibs.printCounts('Other libraries');
  missingLibs.printCounts('Missing libraries');
  componentCount.printCounts('Component count');
  componentSizes.printCounts('Component sizes');
  print('');
  questions.printAnswers();
}
