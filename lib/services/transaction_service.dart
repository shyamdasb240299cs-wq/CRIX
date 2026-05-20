import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

class TransactionService {
  TransactionService();

  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _user => _auth.currentUser;

  String? get _userDocId {
    final user = _user;
    if (user == null) return null;
    return user.email ?? user.uid;
  }

  String? get _boxName {
    final user = _user;
    if (user == null) return null;
    return 'transactions_${user.email ?? user.uid}';
  }

  Future<Box?> _openBox() async {
    final boxName = _boxName;
    if (boxName == null) return null;
    return Hive.isBoxOpen(boxName) ? Hive.box(boxName) : Hive.openBox(boxName);
  }

  Future<List<Map<String, dynamic>>> loadTransactions() async {
    final box = await _openBox();
    if (box == null) return [];

    final rawData = box.get('transactions', defaultValue: []);
    final transactions = normalizeTransactionList(rawData)
      ..sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );
    return transactions;
  }

  Future<Map<String, dynamic>> addTransaction({
    required String name,
    required double amount,
    required bool isIncome,
    String? category,
    DateTime? date,
  }) async {
    final userDocId = _userDocId;
    final box = await _openBox();
    if (userDocId == null || box == null) {
      throw StateError('User not logged in.');
    }

    final transactions = await loadTransactions();
    final txDate = date ?? DateTime.now();
    final normalizedCategory = _normalizeCategory(
      category,
      fallbackTitle: name,
      isIncome: isIncome,
    );
    final id = '${txDate.millisecondsSinceEpoch}_${name.hashCode}';

    final transaction = <String, dynamic>{
      'id': id,
      'name': _cleanTitle(name),
      'amount': amount,
      'isIncome': isIncome,
      'category': normalizedCategory,
      'timestamp': txDate.millisecondsSinceEpoch,
      'date': DateFormat('yyyy-MM-dd').format(txDate),
    };

    transactions.removeWhere((tx) => tx['id'].toString() == id);
    transactions.insert(0, transaction);

    await box.put('transactions', transactions);
    await _syncTransaction(userDocId, transaction);
    _notifyChange();

    return transaction;
  }

  Future<Map<String, dynamic>?> updateTransaction({
    required String id,
    String? name,
    double? amount,
    bool? isIncome,
    String? category,
    DateTime? date,
  }) async {
    final userDocId = _userDocId;
    final box = await _openBox();
    if (userDocId == null || box == null) return null;

    final transactions = await loadTransactions();
    final index = transactions.indexWhere((tx) => tx['id'].toString() == id);
    if (index == -1) return null;

    final existing = Map<String, dynamic>.from(transactions[index]);
    final resolvedIsIncome = isIncome ?? (existing['isIncome'] == true);
    final resolvedName = _cleanTitle(name ?? existing['name']?.toString() ?? '');
    final originalMoment = DateTime.fromMillisecondsSinceEpoch(
      existing['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
    final resolvedMoment = date == null
        ? originalMoment
        : DateTime(
            date.year,
            date.month,
            date.day,
            originalMoment.hour,
            originalMoment.minute,
            originalMoment.second,
            originalMoment.millisecond,
            originalMoment.microsecond,
          );

    existing['name'] = resolvedName;
    existing['amount'] = amount ?? (existing['amount'] as double? ?? 0.0);
    existing['isIncome'] = resolvedIsIncome;
    existing['category'] = _normalizeCategory(
      category ?? existing['category']?.toString(),
      fallbackTitle: resolvedName,
      isIncome: resolvedIsIncome,
    );
    existing['timestamp'] = resolvedMoment.millisecondsSinceEpoch;
    existing['date'] = DateFormat('yyyy-MM-dd').format(resolvedMoment);

    transactions[index] = existing;
    transactions.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    await box.put('transactions', transactions);
    await _syncTransaction(userDocId, existing);
    _notifyChange();

    return existing;
  }

  Future<bool> deleteTransaction(String id) async {
    final userDocId = _userDocId;
    final box = await _openBox();
    if (userDocId == null || box == null) return false;

    final transactions = await loadTransactions();
    final beforeCount = transactions.length;
    transactions.removeWhere((tx) => tx['id'].toString() == id);
    if (transactions.length == beforeCount) return false;

    await box.put('transactions', transactions);
    try {
      await _firestore
          .collection('users')
          .doc(userDocId)
          .collection('transactions')
          .doc(id)
          .delete();
    } catch (_) {
      // Keep the local change even if cloud sync fails.
    }
    _notifyChange();
    return true;
  }

  Future<List<Map<String, dynamic>>> findCandidateTransactions({
    String? id,
    String? title,
    double? amount,
    DateTime? date,
    bool? isIncome,
    String? category,
    String? userText,
    int limit = 3,
  }) async {
    final transactions = await loadTransactions();
    if (transactions.isEmpty) return [];

    if (id != null && id.trim().isNotEmpty) {
      final match = transactions.where(
        (tx) => tx['id'].toString() == id.trim(),
      );
      return match.map((tx) => Map<String, dynamic>.from(tx)).toList();
    }

    final normalizedTitle = _normalize(title);
    final normalizedCategory = _normalize(category);
    final normalizedUserText = _normalize(userText);
    final targetDate = date == null
        ? null
        : DateFormat('yyyy-MM-dd').format(date);

    final scored = <Map<String, dynamic>>[];

    for (var index = 0; index < transactions.length; index++) {
      final tx = transactions[index];
      final txName = _normalize(tx['name']?.toString());
      final txCategory = _normalize(tx['category']?.toString());
      final txAmount = tx['amount'] as double? ?? 0.0;
      final txDate = tx['date']?.toString() ?? '';
      final txIsIncome = tx['isIncome'] == true;

      var score = 0;

      if (normalizedTitle.isNotEmpty) {
        if (txName == normalizedTitle) {
          score += 160;
        } else if (txName.contains(normalizedTitle) ||
            normalizedTitle.contains(txName)) {
          score += 120;
        } else {
          final overlap = _tokenOverlap(txName, normalizedTitle);
          score += overlap * 25;
        }
      }

      if (amount != null) {
        final difference = (txAmount - amount).abs();
        if (difference < 0.01) {
          score += 120;
        } else if (difference <= 1) {
          score += 90;
        } else if (difference <= math.max(10, amount * 0.1)) {
          score += 35;
        }
      }

      if (targetDate != null) {
        if (txDate == targetDate) {
          score += 100;
        } else if (txDate.startsWith(targetDate.substring(0, 7))) {
          score += 15;
        }
      }

      if (isIncome != null && txIsIncome == isIncome) {
        score += 55;
      }

      if (normalizedCategory.isNotEmpty) {
        if (txCategory == normalizedCategory) {
          score += 45;
        } else if (txCategory.contains(normalizedCategory) ||
            normalizedCategory.contains(txCategory)) {
          score += 20;
        }
      }

      if (normalizedUserText.isNotEmpty &&
          txName.isNotEmpty &&
          normalizedUserText.contains(txName)) {
        score += 35;
      }

      score += math.max(0, 12 - index);

      if (score > 0) {
        final enriched = Map<String, dynamic>.from(tx);
        enriched['_score'] = score;
        scored.add(enriched);
      }
    }

    scored.sort(
      (a, b) => (b['_score'] as int).compareTo(a['_score'] as int),
    );

    return scored.take(limit).map((tx) {
      final clean = Map<String, dynamic>.from(tx);
      clean.remove('_score');
      return clean;
    }).toList();
  }

  String buildRecentTransactionsContext(
    List<Map<String, dynamic>> transactions, {
    int limit = 12,
  }) {
    if (transactions.isEmpty) {
      return 'Recent transactions: none yet.';
    }

    final lines = transactions.take(limit).map((tx) {
      final type = tx['isIncome'] == true ? 'income' : 'expense';
      return '- id: ${tx['id']} | $type | title: ${tx['name']} | amount: Rs ${formatAmount(tx['amount'] as double? ?? 0.0)} | category: ${tx['category']} | date: ${tx['date']}';
    }).join('\n');

    return 'Recent transactions:\n$lines';
  }

  String describeTransaction(Map<String, dynamic> tx) {
    final type = tx['isIncome'] == true ? 'income' : 'expense';
    final date = tx['date']?.toString() ?? '';
    final title = tx['name']?.toString() ?? 'Untitled';
    final category = tx['category']?.toString() ?? 'Others';
    final amount = tx['amount'] as double? ?? 0.0;
    return '$title, $type, Rs ${formatAmount(amount)}, $category, $date';
  }

  List<Map<String, dynamic>> normalizeTransactionList(dynamic rawData) {
    if (rawData is! List) return [];

    return rawData.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      map['amount'] = map['amount'] is num
          ? (map['amount'] as num).toDouble()
          : double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0;
      map['isIncome'] = map['isIncome'] == true;
      map['name'] = _cleanTitle(map['name']?.toString() ?? '');
      map['timestamp'] = map['timestamp'] is num
          ? (map['timestamp'] as num).toInt()
          : int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0;

      final fallbackDate = map['timestamp'] as int > 0
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now();

      map['date'] = map['date']?.toString() ??
          DateFormat('yyyy-MM-dd').format(fallbackDate);
      map['id'] = map['id']?.toString() ??
          '${map['timestamp']}_${map['name'].hashCode}';
      map['category'] = _normalizeCategory(
        map['category']?.toString(),
        fallbackTitle: map['name']?.toString() ?? '',
        isIncome: map['isIncome'] == true,
      );
      return map;
    }).toList();
  }

  String formatDateForChat(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  static String formatAmount(double amount) {
    return amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }

  DateTime? tryParseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();

    final direct = DateTime.tryParse(value);
    if (direct != null) {
      return DateTime(direct.year, direct.month, direct.day);
    }

    const formats = <String>[
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd-MM-yyyy',
      'd-M-yyyy',
      'MMM d, yyyy',
      'MMMM d, yyyy',
      'd MMM yyyy',
      'd MMMM yyyy',
    ];

    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parseStrict(value);
        return DateTime(parsed.year, parsed.month, parsed.day);
      } catch (_) {
        // Try the next format.
      }
    }

    return null;
  }

  Future<void> _syncTransaction(
    String userDocId,
    Map<String, dynamic> transaction,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userDocId)
          .collection('transactions')
          .doc(transaction['id'].toString())
          .set(transaction);
    } catch (_) {
      // Keep local changes even if the network request fails.
    }
  }

  String _normalizeCategory(
    String? category, {
    required String fallbackTitle,
    required bool isIncome,
  }) {
    final trimmed = category?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final canonical = _canonicalCategory(trimmed);
      if (canonical != null) return canonical;
    }

    final lowerTitle = fallbackTitle.toLowerCase();
    if (isIncome) {
      if (_containsAny(lowerTitle, ['salary', 'payroll', 'paycheck'])) {
        return 'Salary';
      }
      if (_containsAny(lowerTitle, ['refund', 'reversal'])) {
        return 'Refund';
      }
      if (_containsAny(lowerTitle, ['gift', 'bonus', 'present'])) {
        return 'Gift';
      }
      if (_containsAny(lowerTitle, ['business', 'client', 'freelance', 'invoice'])) {
        return 'Business';
      }
      return 'Others';
    }

    if (_containsAny(lowerTitle, [
      'food',
      'coffee',
      'tea',
      'restaurant',
      'dinner',
      'lunch',
      'breakfast',
      'grocery',
      'groceries',
      'zomato',
      'swiggy',
      'snack',
    ])) {
      return 'Food';
    }
    if (_containsAny(lowerTitle, [
      'uber',
      'ola',
      'taxi',
      'bus',
      'train',
      'flight',
      'fuel',
      'petrol',
      'diesel',
      'travel',
      'metro',
      'cab',
    ])) {
      return 'Travel';
    }
    if (_containsAny(lowerTitle, [
      'amazon',
      'flipkart',
      'myntra',
      'shopping',
      'clothes',
      'shoes',
      'mall',
    ])) {
      return 'Shopping';
    }
    if (_containsAny(lowerTitle, [
      'rent',
      'electricity',
      'wifi',
      'internet',
      'water',
      'bill',
      'emi',
      'recharge',
      'subscription',
    ])) {
      return 'Bills';
    }
    return 'Others';
  }

  String? _canonicalCategory(String input) {
    const categories = <String>[
      'Food',
      'Travel',
      'Shopping',
      'Bills',
      'Salary',
      'Business',
      'Gift',
      'Refund',
      'Others',
    ];

    final normalizedInput = _normalize(input);
    for (final category in categories) {
      if (_normalize(category) == normalizedInput) {
        return category;
      }
    }

    return null;
  }

  String _cleanTitle(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Untitled transaction' : trimmed;
  }

  String _normalize(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _tokenOverlap(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final leftTokens = left.split(' ').where((token) => token.isNotEmpty).toSet();
    final rightTokens = right.split(' ').where((token) => token.isNotEmpty).toSet();
    return leftTokens.intersection(rightTokens).length;
  }

  bool _containsAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }

  void _notifyChange() {
    changeNotifier.value = changeNotifier.value + 1;
  }
}
