/// Utilities for formatting, sorting, and comparing age-based sizes for kids products.
library;

/// Formats a raw size or age string into a clean, age-based display format
/// such as "1 Year", "3 Years", "6 Years", "1-3 Years", "0-1 Month", etc.
String formatKidsSize(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final lower = trimmed.toLowerCase();

  // Pattern: "0-1 month", "0-1 months", "0-1m", "0 - 1 m"
  final monthRangeMatch = RegExp(
    r'^(\d+)\s*-\s*(\d+)\s*(?:months?|m)$',
    caseSensitive: false,
  ).firstMatch(lower);
  if (monthRangeMatch != null) {
    final start = monthRangeMatch.group(1)!;
    final end = monthRangeMatch.group(2)!;
    final endVal = int.tryParse(end) ?? 0;
    final unit = endVal <= 1 ? 'Month' : 'Months';
    return '$start-$end $unit';
  }

  // Pattern: "1-3 years", "1-3 year", "1-3y", "1 - 3 y"
  final yearRangeMatch = RegExp(
    r'^(\d+)\s*-\s*(\d+)\s*(?:years?|y)$',
    caseSensitive: false,
  ).firstMatch(lower);
  if (yearRangeMatch != null) {
    final start = yearRangeMatch.group(1)!;
    final end = yearRangeMatch.group(2)!;
    final endVal = int.tryParse(end) ?? 0;
    final unit = endVal <= 1 ? 'Year' : 'Years';
    return '$start-$end $unit';
  }

  // Pattern: "1-3", "3-6", "6-9", "0-1" (numbers separated by hyphen without unit)
  final numRangeMatch = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(lower);
  if (numRangeMatch != null) {
    final start = numRangeMatch.group(1)!;
    final end = numRangeMatch.group(2)!;
    final endVal = int.tryParse(end) ?? 0;
    final unit = endVal <= 1 ? 'Year' : 'Years';
    return '$start-$end $unit';
  }

  // Pattern: "1 month", "6 months", "1m"
  final singleMonthMatch = RegExp(
    r'^(\d+)\s*(?:months?|m)$',
    caseSensitive: false,
  ).firstMatch(lower);
  if (singleMonthMatch != null) {
    final val = singleMonthMatch.group(1)!;
    final count = int.tryParse(val) ?? 0;
    return count <= 1 ? '$val Month' : '$val Months';
  }

  // Pattern: "1 year", "3 years", "1y", "3y"
  final singleYearMatch = RegExp(
    r'^(\d+)\s*(?:years?|y)$',
    caseSensitive: false,
  ).firstMatch(lower);
  if (singleYearMatch != null) {
    final val = singleYearMatch.group(1)!;
    final count = int.tryParse(val) ?? 0;
    return count <= 1 ? '$val Year' : '$val Years';
  }

  // Pattern: single number e.g. "0", "1", "3", "6", "10"
  final singleDigitMatch = RegExp(r'^(\d+)$').firstMatch(trimmed);
  if (singleDigitMatch != null) {
    final val = int.tryParse(singleDigitMatch.group(1)!) ?? 0;
    if (val == 0) {
      return '0-1 Year';
    } else if (val == 1) {
      return '1 Year';
    } else {
      return '$val Years';
    }
  }

  // If already formatted like "1 Year", "3 Years", "1-3 Years", etc.
  return trimmed;
}

/// Checks if a size string looks like a kids age size (e.g. "0", "1", "3", "1-3 years", "0-6M", etc.)
bool isKidsAgeSize(String? raw) {
  if (raw == null) return false;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;

  // Single number like 0, 1, 3, 6
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return true;

  // Hyphenated range with optional units
  if (RegExp(
    r'^\d+\s*-\s*\d+\s*(?:m|y|months?|years?)?$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }

  // Single number with age units like 1M, 6M, 1Y, 3Y, 1 Year, 3 Years
  if (RegExp(
    r'^\d+\s*(?:m|y|months?|years?)$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }

  return false;
}

/// Checks if two size strings represent equivalent sizes, handling casing,
/// formatting differences (e.g. "1-3 years" == "1-3 Years" == "1-3Y" or "1" == "1 Year").
bool areKidsSizesEquivalent(String? a, String? b) {
  if (a == null || b == null) return false;
  final at = a.trim();
  final bt = b.trim();
  if (at.isEmpty || bt.isEmpty) return false;
  if (at.toUpperCase() == bt.toUpperCase()) return true;

  final fa = formatKidsSize(at).toUpperCase();
  final fb = formatKidsSize(bt).toUpperCase();
  if (fa == fb && fa.isNotEmpty) return true;

  // Normalization comparison: strip non-alphanumeric except hyphen
  final na = at.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final nb = bt.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (na == nb) return true;

  return false;
}

/// Parses any kids size label into inclusive month bounds (minMonths, maxMonths).
(int, int) kidsSizeToMonthRange(String raw) {
  final formatted = formatKidsSize(raw).toLowerCase();

  final mRange = RegExp(r'^(\d+)-(\d+)\s*month').firstMatch(formatted);
  if (mRange != null) {
    return (int.parse(mRange.group(1)!), int.parse(mRange.group(2)!));
  }
  final yRange = RegExp(r'^(\d+)-(\d+)\s*year').firstMatch(formatted);
  if (yRange != null) {
    return (int.parse(yRange.group(1)!) * 12, int.parse(yRange.group(2)!) * 12);
  }
  final sMonth = RegExp(r'^(\d+)\s*month').firstMatch(formatted);
  if (sMonth != null) {
    final m = int.parse(sMonth.group(1)!);
    return (m, m);
  }
  final sYear = RegExp(r'^(\d+)\s*year').firstMatch(formatted);
  if (sYear != null) {
    final y = int.parse(sYear.group(1)!);
    return (y * 12, y * 12);
  }
  return (999, 999);
}

/// Compares kids sizes so they appear chronologically from youngest to oldest.
int compareKidsSizes(String a, String b) {
  final ra = kidsSizeToMonthRange(a);
  final rb = kidsSizeToMonthRange(b);
  if (ra.$1 != rb.$1) return ra.$1.compareTo(rb.$1);
  return ra.$2.compareTo(rb.$2);
}
