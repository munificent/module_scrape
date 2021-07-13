// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:math';

class YesNo {
  final Map<String, List<int>> _questions = {};

  void add(String question, bool answer) {
    var answers = _questions.putIfAbsent(question, () => [0, 0]);
    answers[answer ? 0 : 1]++;
  }

  void printAnswers() {
    var longest = 0;
    for (var question in _questions.keys) {
      longest = max(question.length, longest);
    }

    for (var question in _questions.keys) {
      var answers = _questions[question];
      var yes = answers[0];
      var no = answers[1];
      var total = yes + no;
      var percent = (100.0 * yes / total).toStringAsFixed(2);
      print('${question.padRight(longest + 1)}: $yes / $total ($percent%)');
    }
  }
}
