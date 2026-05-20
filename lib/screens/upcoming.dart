import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import '../services/transaction_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final TransactionService _transactionService = TransactionService();
  late Box box;
  List<Map<String, dynamic>> allTransactions = [];
  Map<String, List<Map<String, dynamic>>> groupedTransactions = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    TransactionService.changeNotifier.addListener(_handleTransactionsChanged);
    loadTransactions();
  }

  @override
  void dispose() {
    TransactionService.changeNotifier.removeListener(
      _handleTransactionsChanged,
    );
    super.dispose();
  }

  void _handleTransactionsChanged() {
    if (!mounted) return;
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    if (user == null) return;

    box = await Hive.openBox('transactions_${(user!.email ?? user!.uid)}');
    final rawData = box.get('transactions', defaultValue: []);
    allTransactions = _normalizeTransactionList(rawData);

    // Group transactions by date
    groupedTransactions = {};
    for (var tx in allTransactions) {
      final date = tx['date'] as String;
      if (!groupedTransactions.containsKey(date)) {
        groupedTransactions[date] = [];
      }
      groupedTransactions[date]!.add(tx);
    }

    // Sort dates in descending order
    final sortedKeys = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final sortedGrouped = Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, groupedTransactions[key]!)),
    );
    groupedTransactions = sortedGrouped;

    // Sort transactions within each date by timestamp descending
    for (var date in groupedTransactions.keys) {
      groupedTransactions[date]!.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );
    }

    setState(() => isLoading = false);
  }

  Future<void> deleteTransaction(String id) async {
    try {
      final deleted = await _transactionService.deleteTransaction(id);
      if (deleted) {
        await loadTransactions();
      }
    } catch (_) {
      // Continue if Firestore fails, local is updated
    }
  }

  List<Map<String, dynamic>> _normalizeTransactionList(dynamic rawData) {
    if (rawData is! List) return [];

    return rawData.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      map['amount'] = map['amount'] is num
          ? (map['amount'] as num).toDouble()
          : double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0;
      map['isIncome'] = map['isIncome'] == true;
      map['name'] = map['name']?.toString() ?? '';
      map['timestamp'] = map['timestamp'] is num
          ? (map['timestamp'] as num).toInt()
          : int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0;
      map['date'] =
          map['date']?.toString() ??
          DateFormat('yyyy-MM-dd').format(
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
          );
      map['id'] =
          map['id']?.toString() ??
          '${map['timestamp']}_${map['name'].hashCode}';
      return map;
    }).toList();
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final transactionDate = DateTime(date.year, date.month, date.day);

    if (transactionDate == today) {
      return 'Today';
    } else if (transactionDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        title: const Text(
          "Transaction History",
          style: TextStyle(
            fontFamily: 'Qarume',
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF09090B), Color(0xFF14141A)],
          ),
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              )
            : groupedTransactions.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.only(
                  top: 120,
                  bottom: 40,
                  left: 24,
                  right: 24,
                ),
                itemCount: groupedTransactions.length,
                itemBuilder: (context, index) {
                  final date = groupedTransactions.keys.elementAt(index);
                  final transactions = groupedTransactions[date]!;
                  final totalSpent = transactions
                      .where((tx) => !tx['isIncome'])
                      .fold(0.0, (total, tx) => total + tx['amount']);
                  final totalEarned = transactions
                      .where((tx) => tx['isIncome'])
                      .fold(0.0, (total, tx) => total + tx['amount']);

                  return _buildTimelineBlock(
                    date,
                    totalEarned,
                    totalSpent,
                    transactions,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Icon(
              Icons.history_toggle_off_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            "It's quiet here...",
            style: TextStyle(
              fontFamily: 'Qarume',
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Your transaction history will elegantly\nappear here over time.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Qarume',
              color: Colors.white38,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBlock(
    String date,
    double earned,
    double spent,
    List<Map<String, dynamic>> transactions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Glowing Sticky Header
        Container(
          margin: const EdgeInsets.only(bottom: 20, top: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _formatDate(date),
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Color(0xFF818CF8),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    fontSize: 14,
                  ),
                ),
              ),
              Row(
                children: [
                  if (earned > 0)
                    Text(
                      "+₹${earned.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontFamily: 'Qarume',
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  if (earned > 0 && spent > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text("•", style: TextStyle(color: Colors.white38)),
                    ),
                  if (spent > 0)
                    Text(
                      "-₹${spent.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontFamily: 'Qarume',
                        color: Color(0xFFF43F5E),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Transaction Cards Timeline
        Stack(
          children: [
            // Timeline Line
            Positioned(
              left: 23,
              top: 10,
              bottom: 10,
              child: Container(width: 2, color: const Color(0xFF27272A)),
            ),
            Column(
              children: transactions
                  .map((tx) => _buildTransactionCard(tx))
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final bool isIncome = tx['isIncome'] ?? false;
    final String amountStr =
        "${isIncome ? '+' : '-'}₹${(tx['amount'] as double).toStringAsFixed(0)}";

    return GestureDetector(
      onLongPress: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: const Color(0xFF18181B).withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF27272A)),
              ),
              title: const Text(
                "Delete Transaction",
                style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
              ),
              content: const Text(
                "Are you sure you want to delete this transaction from history?",
                style: TextStyle(fontFamily: 'Qarume', color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(fontFamily: 'Qarume', color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF43F5E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    "Delete",
                    style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );

        if (confirm == true) {
          deleteTransaction(tx['id']);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            // Timeline Dot + Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF27272A), width: 3),
              ),
              child: Icon(
                isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: isIncome
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF43F5E),
                size: 18,
              ),
            ),
            const SizedBox(width: 16),

            // Rich Card Content
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF27272A).withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx['name'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Qarume',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      amountStr,
                      style: TextStyle(
                        fontFamily: 'Qarume',
                        color: isIncome
                            ? const Color(0xFF10B981)
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
