// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:math';

import 'package:module_scrape/src/import_graph.dart';
import 'package:module_scrape/src/histogram.dart';
import 'package:module_scrape/src/yes_no.dart';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

final importCycleCounts = Histogram(order: SortOrder.numeric);
final importComponentSizes = Histogram(order: SortOrder.numeric);
final importCycleLocations = Histogram();
final classUseCounts = Histogram(order: SortOrder.numeric);

final questions = YesNo();

final random = Random(1234);

void main(List<String> arguments) {
  int percent;

  var parser = ArgParser();
  parser.addOption('percent',
      abbr: 'p',
      defaultsTo: '100',
      callback: (value) => percent = int.parse(value));

  var argResults = parser.parse(arguments);

  var directory = argResults.rest.first;
  var packageDirs = Directory(directory)
      .listSync()
      .whereType<Directory>()
      .map((entry) => entry.path)
      .toList();
  packageDirs.sort();

  for (var packageDir in packageDirs) {
    if (random.nextInt(100) > percent) continue;

    var packageName = p.basename(packageDir);

    // Skip Dart team packages with lots of language tests.
    if (packageName.startsWith('analyzer-')) continue;
    if (packageName.startsWith('_fe_analyzer_shared-')) continue;

    // Strip off a version number if there is one.
    var dash = packageName.indexOf('-');
    if (dash != -1) {
      packageName = packageName.substring(0, dash);
    }

    print(packageDir);
    var graph = ImportGraph.read(packageName, packageDir);

    var importComponents = graph.connectedComponents({'import'});
    for (var component in importComponents) {
      importComponentSizes.add(component.length);

      if (component.length > 1) {
        var dirs = <String>{};
        for (var library in component) {
          dirs.add(p.split(library)[0]);
          var sorted = dirs.toList();
          importCycleLocations.add(sorted.join('+'));
        }
      }
    }

    importCycleCounts.add(
        importComponents.where((component) => component.length > 1).length);

    questions.add('Package has any import cycle',
        importComponents.any((component) => component.length > 1));

    countComponentLibraries(graph, 'Lib is in import cycle', importComponents);

    var hasClassUse = false;
    graph.libraries.forEach((library, node) {
      var allUses = {
        ...node.superclasses,
        ...node.superinterfaces,
        ...node.mixins
      };

      if (allUses.isNotEmpty) hasClassUse = true;

      questions.add(
          'Lib extends at least one other lib', node.superclasses.isNotEmpty);
      questions.add('Lib implements at least one other lib',
          node.superinterfaces.isNotEmpty);
      questions.add(
          'Lib mixes in at least one other lib', node.mixins.isNotEmpty);
      questions.add('Lib uses class in any way from at least one other lib',
          allUses.isNotEmpty);

      classUseCounts.add(allUses.length);
    });

    questions.add('Package has any cross-library class use', hasClassUse);
  }

  importComponentSizes.printCounts('Number of libraries in import cycle');
  importCycleCounts.printCounts('Number of import cycles in package');
  importCycleLocations.printCounts('Import cycle directories');
  classUseCounts
      .printCounts('Number of other libraries whose classes a library uses');
  print('');
  questions.printAnswers();
}

void countComponentLibraries(
    ImportGraph graph, String question, List<List<String>> components) {
  for (var component in components) {
    for (var _ in component) {
      questions.add(question, component.length > 1);
    }
  }
}
