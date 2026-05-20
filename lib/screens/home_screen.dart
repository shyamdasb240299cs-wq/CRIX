import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/crixy_floating.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/overlay_service.dart';
import '../services/transaction_service.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Box box;
  final user = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;
  final TransactionService _transactionService = TransactionService();

  double totalSpentToday = 0;
  double totalEarnedToday = 0;
  double yesterdaySpent = 0;
  double spendingLimit = 0;
  bool isLimitTodayOnly = true;
  List<Map<String, dynamic>> allTransactions = [];
  List<Map<String, dynamic>> transactionsToday = [];
  bool isLoading = true;
  bool isOverlayEnabled = false;

  void syncOverlayData() {
    if (!isOverlayEnabled) return;
    OverlayService.updateOverlay(
      expense: totalSpentToday,
      limit: spendingLimit,
      left: spendingLimit > 0
          ? (spendingLimit - totalSpentToday).clamp(0.0, double.infinity)
          : 0.0,
      income: totalEarnedToday,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TransactionService.changeNotifier.addListener(_handleTransactionsChanged);
    initializeData();
    OverlayService.initializeListener(
      onOverlayClosed: () async {
        if (mounted) {
          setState(() {
            isOverlayEnabled = false;
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('overlay_enabled', false);
        }
      },
      onOverlayAddTx: (name, amount, isIncome, category) {
        if (mounted) {
          addTransaction(name, amount, isIncome, category, fromOverlay: true);
        }
      },
    );
  }

  @override
  void dispose() {
    TransactionService.changeNotifier.removeListener(
      _handleTransactionsChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleTransactionsChanged() {
    if (!mounted || user == null) return;
    final boxName = 'transactions_${user!.email ?? user!.uid}';
    if (!Hive.isBoxOpen(boxName)) return;
    box = Hive.box(boxName);
    loadLocalTransactions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      processPendingTxs();
    }
  }

  Future<void> processPendingTxs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Ensure we get fresh data written by Kotlin
    final pendingString = prefs.getString("pending_txs") ?? "[]";
    if (pendingString != "[]") {
      try {
        final List<dynamic> pending = jsonDecode(pendingString);
        for (var tx in pending) {
          await addTransaction(
            tx['name'] as String,
            (tx['amount'] as num).toDouble(),
            tx['isIncome'] == true,
            tx['category'] as String? ?? 'Others',
            fromOverlay: true,
          );
        }
        await prefs.setString("pending_txs", "[]");
      } catch (e) {
        debugPrint('Error parsing pending txs: $e');
      }
    }
  }

  Future<void> initializeData() async {
    if (user == null) return;

    box = await Hive.openBox('transactions_${(user!.email ?? user!.uid)}');
    loadLocalTransactions();
    loadSpendingLimit();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool savedEnabled = prefs.getBool('overlay_enabled') ?? false;

    bool actuallyRunning = await OverlayService.isOverlayActive();

    isOverlayEnabled = savedEnabled && actuallyRunning;
    if (savedEnabled != isOverlayEnabled) {
      await prefs.setBool('overlay_enabled', isOverlayEnabled);
    }

    setState(() => isLoading = false);

    // Sync with Firestore in the background after loading Hive.
    syncFromFirestore();

    // Check queue from Android background widget after initializing hive variables
    await processPendingTxs();

    if (isOverlayEnabled) {
      syncOverlayData();
    }
  }

  void loadLocalTransactions() {
    final rawData = box.get('transactions', defaultValue: []);
    allTransactions = _normalizeTransactionList(rawData);
    _updateDailyViews();
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
      map['category'] = map['category']?.toString() ?? 'Others';
      return map;
    }).toList();
  }

  void _updateDailyViews() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterday = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now().subtract(const Duration(days: 1)));

    allTransactions.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    transactionsToday = allTransactions
        .where((tx) => tx['date'] == today)
        .toList();

    totalSpentToday = 0;
    totalEarnedToday = 0;
    yesterdaySpent = 0;

    for (var tx in transactionsToday) {
      final amount = tx['amount'] as double;
      if (tx['isIncome'] == true) {
        totalEarnedToday += amount;
      } else {
        totalSpentToday += amount;
      }
    }

    for (var tx in allTransactions.where(
      (tx) => tx['date'] == yesterday && tx['isIncome'] == false,
    )) {
      yesterdaySpent += tx['amount'] as double;
    }

    if (mounted) setState(() {});
    syncOverlayData();
  }

  double getSpendingPercentageChange() {
    if (yesterdaySpent == 0) return 0.0;
    return ((totalSpentToday - yesterdaySpent) / yesterdaySpent) * 100;
  }

  Future<void> syncFromFirestore() async {
    try {
      var snapshot = await firestore
          .collection('users')
          .doc((user!.email ?? user!.uid))
          .collection('transactions')
          .get();

      if (snapshot.docs.isEmpty &&
          user!.email != null &&
          user!.uid != user!.email) {
        final legacySnapshot = await firestore
            .collection('users')
            .doc(user!.uid)
            .collection('transactions')
            .get();
        if (legacySnapshot.docs.isNotEmpty) {
          snapshot = legacySnapshot;
        }
      }

      final remoteTransactions = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? '',
          'amount': data['amount'] is num
              ? (data['amount'] as num).toDouble()
              : double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0,
          'isIncome': data['isIncome'] == true,
          'timestamp': data['timestamp'] is num
              ? (data['timestamp'] as num).toInt()
              : int.tryParse(data['timestamp']?.toString() ?? '0') ?? 0,
          'category': data['category']?.toString() ?? 'Others',
          'date':
              data['date']?.toString() ??
              DateFormat('yyyy-MM-dd').format(DateTime.now()),
        };
      }).toList();

      final localMap = {
        for (var tx in allTransactions) tx['id'].toString(): tx,
      };

      final mergedTransactions = <Map<String, dynamic>>[];
      for (var remote in remoteTransactions) {
        final local = localMap.remove(remote['id'].toString());
        mergedTransactions.add(local ?? remote);
      }

      if (localMap.isNotEmpty) {
        mergedTransactions.addAll(localMap.values);
        for (var tx in localMap.values) {
          await firestore
              .collection('users')
              .doc((user!.email ?? user!.uid))
              .collection('transactions')
              .doc(tx['id'].toString())
              .set(tx);
        }
      }

      allTransactions = mergedTransactions;
      await box.put('transactions', allTransactions);
      _updateDailyViews();
    } catch (_) {
      // Keep local data if Firestore sync fails.
    }
  }

  void loadSpendingLimit() {
    spendingLimit = box.get('spending_limit', defaultValue: 0.0);
    isLimitTodayOnly = box.get('limit_today_only', defaultValue: true);
  }

  Future<void> saveSpendingLimit(double limit, bool todayOnly) async {
    spendingLimit = limit;
    isLimitTodayOnly = todayOnly;
    await box.put('spending_limit', limit);
    await box.put('limit_today_only', todayOnly);

    // Save to Firestore silently in background (no await)
    try {
      firestore
          .collection('users')
          .doc((user!.email ?? user!.uid))
          .collection('settings')
          .doc('spending_limit')
          .set({
            'limit': limit,
            'todayOnly': todayOnly,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Continue if Firestore fails
    }

    if (mounted) setState(() {});
    syncOverlayData();
  }

  Future<bool> addTransaction(
    String name,
    double amount,
    bool isIncome,
    String category, {
    bool fromOverlay = false,
  }) async {
    // Check spending limit for expenses
    if (!isIncome && spendingLimit > 0) {
      final newTotalSpent = totalSpentToday + amount;
      if (newTotalSpent > spendingLimit) {
        if (!fromOverlay) {
          final shouldContinue = await showLimitExceededDialog(amount);
          if (!shouldContinue) return false;
        }
      }
    }

    try {
      final transaction = await _transactionService.addTransaction(
        name: name,
        amount: amount,
        isIncome: isIncome,
        category: category,
      );
      allTransactions.removeWhere(
        (tx) => tx['id'].toString() == transaction['id'].toString(),
      );
      allTransactions.insert(0, transaction);
      _updateDailyViews();
    } catch (e) {
      debugPrint('❌ LOCAL ERROR: $e');
      return false;
    }
    return true;
  }

  Future<void> deleteTransaction(String id) async {
    try {
      final deleted = await _transactionService.deleteTransaction(id);
      if (deleted) {
        allTransactions.removeWhere((tx) => tx['id'] == id);
        _updateDailyViews();
      }
    } catch (_) {
      // Keep going if Firestore fails
    }
  }

  Future<bool> showLimitExceededDialog(double amount) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: const Color(0xFF18181B).withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF27272A)),
              ),
              title: const Text(
                "Limit Reached",
                style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
              ),
              content: const Text(
                "Limit reached. Do you want to continue?",
                style: TextStyle(fontFamily: 'Qarume', color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
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
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text(
                    "Continue",
                    style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  // 🔥 POPUP
  void openAddPopup() {
    String name = "";
    String amount = "";
    bool isIncome = false;
    String category = "Others";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return GestureDetector(
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xD909090B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                border: Border(top: BorderSide(color: Color(0xFF27272A))),
              ),
              child: StatefulBuilder(
                builder: (builderContext, setModalState) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 24,
                      bottom:
                          MediaQuery.of(sheetContext).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Text(
                          "New Transaction",
                          style: TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),

                        TextField(
                          style: const TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: "What was this for?",
                            hintStyle: const TextStyle(
                              fontFamily: 'Qarume',
                              color: Colors.white38,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF18181B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          onChanged: (val) => name = val,
                        ),

                        const SizedBox(height: 16),

                        TextField(
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                            fontSize: 24,
                          ),
                          decoration: InputDecoration(
                            hintText: "₹ 0",
                            hintStyle: const TextStyle(
                              fontFamily: 'Qarume',
                              color: Colors.white38,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF18181B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          onChanged: (val) => amount = val,
                        ),

                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    isIncome = false;
                                    category = "Others";
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isIncome
                                        ? const Color(
                                            0xFFF43F5E,
                                          ).withValues(alpha: 0.15)
                                        : const Color(0xFF18181B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: !isIncome
                                          ? const Color(0xFFF43F5E)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Expense",
                                      style: TextStyle(
                                        fontFamily: 'Qarume',
                                        color: !isIncome
                                            ? const Color(0xFFF43F5E)
                                            : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    isIncome = true;
                                    category = "Others";
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isIncome
                                        ? const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.15)
                                        : const Color(0xFF18181B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isIncome
                                          ? const Color(0xFF10B981)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Income",
                                      style: TextStyle(
                                        fontFamily: 'Qarume',
                                        color: isIncome
                                            ? const Color(0xFF10B981)
                                            : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children:
                                (isIncome
                                        ? [
                                            "Salary",
                                            "Freelance",
                                            "Business",
                                            "Gift",
                                            "Refund",
                                            "Others",
                                          ]
                                        : [
                                            "Food",
                                            "Travel",
                                            "Shopping",
                                            "Bills",
                                            "Others",
                                          ])
                                    .map((cat) {
                                      final isSelected = category == cat;
                                      return GestureDetector(
                                        onTap: () =>
                                            setModalState(() => category = cat),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF6366F1)
                                                : const Color(0xFF18181B),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF6366F1)
                                                  : const Color(0xFF27272A),
                                            ),
                                          ),
                                          child: Text(
                                            cat,
                                            style: TextStyle(
                                              fontFamily: 'Qarume',
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white54,
                                              fontSize: 14,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                          ),
                        ),
                        const SizedBox(height: 32),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            if (name.isNotEmpty && amount.isNotEmpty) {
                              final parsedAmount = double.tryParse(amount);
                              if (parsedAmount != null && parsedAmount > 0) {
                                final success = await addTransaction(
                                  name,
                                  parsedAmount,
                                  isIncome,
                                  category,
                                );
                                if (success && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              }
                            }
                          },
                          child: const Text(
                            "Add Transaction",
                            style: TextStyle(
                              fontFamily: 'Qarume',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void openSpendingLimitPopup() {
    String limitAmount = spendingLimit.toStringAsFixed(0);
    bool todayOnly = isLimitTodayOnly;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: const Color(0xFF18181B).withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF27272A)),
            ),
            title: const Text(
              "Set Spending Limit",
              style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: limitAmount),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: "Enter limit amount",
                    hintStyle: const TextStyle(
                      fontFamily: 'Qarume',
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF09090B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => limitAmount = val,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text(
                          "Today",
                          style: TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        value: true,
                        groupValue: todayOnly,
                        onChanged: (val) =>
                            setState(() => todayOnly = val ?? true),
                        activeColor: const Color(0xFF6366F1),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text(
                          "Always",
                          style: TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        value: false,
                        groupValue: todayOnly,
                        onChanged: (val) =>
                            setState(() => todayOnly = val ?? false),
                        activeColor: const Color(0xFF6366F1),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(fontFamily: 'Qarume', color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  final limit = double.tryParse(limitAmount) ?? 0;
                  saveSpendingLimit(limit, todayOnly);
                  Navigator.pop(context);
                },
                child: const Text(
                  "Save",
                  style: TextStyle(fontFamily: 'Qarume', color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      floatingActionButton: const CrixyFloatingButton(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'CRIX',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Qarume',
                      color: Colors.white,
                    ),
                  ),
                  AnimatedProfileIcon(),
                ],
              ),

              const SizedBox(height: 30),

              // MAIN CARD WITH GLOW
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                  ),
                ),
                child: Stack(
                  children: [
                    // Inner decorations removed
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              "Total Spent Today",
                              style: TextStyle(
                                fontFamily: 'Qarume',
                                color: Colors.white70,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "₹${totalSpentToday.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontFamily: 'Qarume',
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                                if (yesterdaySpent != 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      "${getSpendingPercentageChange().abs().toStringAsFixed(0)}% spent ${totalSpentToday > yesterdaySpent ? 'more' : 'less'} than yesterday",
                                      style: TextStyle(
                                        fontFamily: 'Qarume',
                                        color: totalSpentToday > yesterdaySpent
                                            ? const Color(0xFFF43F5E)
                                            : const Color(0xFF10B981),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (spendingLimit > 0)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        "Limit: ₹${spendingLimit.toStringAsFixed(0)}",
                                        style: const TextStyle(
                                          fontFamily: 'Qarume',
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: LinearProgressIndicator(
                                          value: spendingLimit > 0
                                              ? (totalSpentToday /
                                                        spendingLimit)
                                                    .clamp(0.0, 1.0)
                                              : 0,
                                          backgroundColor: Colors.black26,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                totalSpentToday > spendingLimit
                                                    ? const Color(0xFFF43F5E)
                                                    : const Color(0xFF10B981),
                                              ),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        totalSpentToday > spendingLimit
                                            ? "Limit exceeded by ₹${(totalSpentToday - spendingLimit).toStringAsFixed(0)}"
                                            : "Left: ₹${(spendingLimit - totalSpentToday).toStringAsFixed(0)}",
                                        style: TextStyle(
                                          fontFamily: 'Qarume',
                                          color: totalSpentToday > spendingLimit
                                              ? const Color(0xFFF43F5E)
                                              : const Color(0xFF10B981),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "Earned Today: ₹${totalEarnedToday.toStringAsFixed(0)}",
                          style: const TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white70,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ACTIONS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await Navigator.pushNamed(context, '/analytics');
                      loadLocalTransactions();
                    },
                    child: actionIcon(
                      Icons.bar_chart_rounded,
                      "Stats",
                      const Color(0xFF8B5CF6),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.pushNamed(context, '/upcoming');
                      loadLocalTransactions();
                    },
                    child: actionIcon(
                      Icons.history_rounded,
                      "History",
                      const Color(0xFF3B82F6),
                    ),
                  ),
                  GestureDetector(
                    onTap: openSpendingLimitPopup,
                    child: actionIcon(
                      Icons.account_balance_wallet_rounded,
                      "Limit",
                      const Color(0xFF10B981),
                    ),
                  ),
                  GestureDetector(
                    onTap: openAddPopup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            color: Color(0xFF6366F1),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Add",
                            style: TextStyle(
                              fontFamily: 'Qarume',
                              color: Color(0xFF6366F1),
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

              // UI: Overlay Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF6366F1),
                inactiveTrackColor: const Color(0xFF27272A),
                title: const Text(
                  "Enable Floating Widget",
                  style: TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Show wallet summary over other apps",
                  style: TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                value: isOverlayEnabled,
                onChanged: (val) async {
                  if (val) {
                    bool hasPerm = await OverlayService.checkPermission();
                    if (!hasPerm) {
                      await OverlayService.requestPermission();
                      hasPerm = await OverlayService.checkPermission();
                    }
                    if (hasPerm) {
                      setState(() => isOverlayEnabled = true);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('overlay_enabled', true);

                      await OverlayService.startOverlay(
                        expense: totalSpentToday,
                        limit: spendingLimit,
                        left: spendingLimit > 0
                            ? (spendingLimit - totalSpentToday).clamp(
                                0.0,
                                double.infinity,
                              )
                            : 0.0,
                        income: totalEarnedToday,
                      );
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Overlay permission needed',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }
                    }
                  } else {
                    setState(() => isOverlayEnabled = false);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('overlay_enabled', false);
                    await OverlayService.stopOverlay();
                  }
                },
              ),

              const SizedBox(height: 20),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Recent Transactions",
                  style: TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: transactionsToday.isEmpty
                    ? const Center(
                        child: Text(
                          "No transactions yet",
                          style: TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white38,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: transactionsToday.length,
                        itemBuilder: (context, index) {
                          final tx = transactionsToday[index];
                          return transactionItem(
                            tx["id"].toString(),
                            tx["name"].toString(),
                            tx["amount"] as double,
                            tx["isIncome"] as bool,
                            tx["timestamp"] as int? ?? 0,
                            tx["category"]?.toString() ?? 'Others',
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget actionIcon(IconData icon, String label, Color tint) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: tint, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Qarume',
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
        return const Color(0xFFF43F5E);
      case 'Travel':
        return const Color(0xFF3B82F6);
      case 'Shopping':
        return const Color(0xFF10B981);
      case 'Bills':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }

  Widget transactionItem(
    String id,
    String name,
    double amount,
    bool isIncome,
    int timestamp,
    String category,
  ) {
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
                "Are you sure you want to delete this transaction? This action cannot be undone.",
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
          deleteTransaction(id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF27272A).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isIncome
                          ? const Color(0xFF10B981).withValues(alpha: 0.1)
                          : const Color(0xFFF43F5E).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIncome
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: isIncome
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Qarume',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              timestamp > 0
                                  ? DateFormat('h:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        timestamp,
                                      ),
                                    )
                                  : "Just now",
                              style: const TextStyle(
                                fontFamily: 'Qarume',
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(
                                  category,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _getCategoryColor(
                                    category,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  fontFamily: 'Qarume',
                                  color: _getCategoryColor(category),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              "${isIncome ? '+' : '-'}₹${amount.toStringAsFixed(0)}",
              style: TextStyle(
                fontFamily: 'Qarume',
                color: isIncome ? const Color(0xFF10B981) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedProfileIcon extends StatefulWidget {
  const AnimatedProfileIcon({super.key});

  @override
  State<AnimatedProfileIcon> createState() => _AnimatedProfileIconState();
}

class _AnimatedProfileIconState extends State<AnimatedProfileIcon> {
  bool isPressed = false;

  void _onTapDown(TapDownDetails details) {
    setState(() => isPressed = true);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => isPressed = false);
  }

  void _onTapCancel() {
    setState(() => isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        Navigator.pushNamed(context, '/profile');
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: isPressed ? 0.9 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF18181B),
          ),
          child: const Icon(Icons.person, color: Colors.white70),
        ),
      ),
    );
  }
}
