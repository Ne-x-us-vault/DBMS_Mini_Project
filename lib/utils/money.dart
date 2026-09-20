int toPaise(double rupees) => (rupees * 100).round();

String fmtPaise(int paiseObj) {
  final sign = paiseObj < 0 ? '-' : '';
  final abs = paiseObj.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$sign₹$whole.$frac';
}

String paiseToInput(int paiseObj) => (paiseObj / 100).toStringAsFixed(2);

String fmtShares(Map<String, int> shares) {
  return shares.entries
      .map((e) => '${e.key}: ${fmtPaise(e.value)}')
      .join(' · ');
}