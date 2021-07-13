// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:math' as math;

/// Counts occurrences of numbers and displays the results as a histogram.
class Histogram {
  /// Keys are numbers and values are how many times that number has appeared.
  final Map<int, int> _counts = {};

  int get totalCount => _counts.values.fold(0, (a, b) => a + b);

  void add(int item) {
    _counts.putIfAbsent(item, () => 0);
    _counts[item]++;
  }

  void printCounts(String label) {
    var total = totalCount;
    print('');
    print('-- $label ($total total) --');

    var keys = _counts.keys.toList();
    keys.sort();

    var longest = keys.fold<int>(
        0, (length, key) => math.max(length, key.toString().length));
    var barScale = 80 - 22 - longest;

    var skipped = 0;
    for (var object in keys) {
      var count = _counts[object];
      var countString = count.toString().padLeft(7);
      var percent = 100 * count / total;
      var percentString = percent.toStringAsFixed(3).padLeft(7);

      if (percent >= 1.0) {
        var line = '$countString ($percentString%): $object';
        if (barScale > 1) {
          line = line.padRight(longest + 22);
          line += '=' * (percent / 100 * barScale).ceil();
        }
        print(line);
      } else {
        skipped++;
      }
    }

    if (skipped > 0) print('And $skipped more...');

    // If we're counting numeric keys, show other statistics too.
    var sum = keys.fold<int>(0, (result, key) => result + key * _counts[key]);
    var average = sum / total;

    // Find the median key where half the total count is below it.
    var count = 0;
    var median = -1;
    for (var key in keys) {
      count += _counts[key];
      if (count >= total ~/ 2) {
        median = key;
        break;
      }
    }

    print('Sum $sum, average ${average.toStringAsFixed(3)}, median $median');
  }
}
