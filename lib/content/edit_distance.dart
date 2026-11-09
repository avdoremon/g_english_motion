/// Levenshtein edit distance between [a] and [b], ignoring case.
int editDistance(String a, String b) {
  a = a.toLowerCase();
  b = b.toLowerCase();
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      final sub =
          prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      final ins = cur[j - 1] + 1;
      final del = prev[j] + 1;
      cur.add(sub < ins ? (sub < del ? sub : del) : (ins < del ? ins : del));
    }
    prev = cur;
  }
  return prev.last;
}
