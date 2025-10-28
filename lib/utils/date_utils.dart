// utils/date_utils.dart
bool isAfterToday(DateTime d) {
  final today = DateTime.now().toLocal();
  final t = DateTime(today.year, today.month, today.day);
  final x = d.toLocal();
  final dx = DateTime(x.year, x.month, x.day);
  return dx.isAfter(t);
}

bool isTodayOrBefore(DateTime d) {
  final today = DateTime.now().toLocal();
  final t = DateTime(today.year, today.month, today.day);
  final x = d.toLocal();
  final dx = DateTime(x.year, x.month, x.day);
  return !dx.isAfter(t); // 오늘이거나 과거
}
