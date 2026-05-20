import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/crixy_floating.dart';
import '../services/transaction_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> allTransactions = [];
  double todayExpense = 0;
  double yesterdayExpense = 0;
  double weeklyExpense = 0;
  double monthlyExpense = 0;
  double dailyAverage = 0;
  double spendingLimit = 0.0;
  bool isIncomeMode = false;

  Map<String, double> dailyCat = {};
  Map<String, double> weeklyCat = {};
  Map<String, double> monthlyCat = {};

  List<Map<String, dynamic>> todayDailyTxs = [];
  List<Map<String, dynamic>> yesterdayDailyTxs = [];
  List<double> weeklyDaily = List.filled(7, 0.0);
  List<double> monthlyDaily = List.filled(31, 0.0);

  int dailyOffset = 0;
  int weeklyOffset = 0;
  int monthlyOffset = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    TransactionService.changeNotifier.addListener(_loadData);
    _loadData();
  }

  void _loadData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final boxName = 'transactions_${user.email ?? user.uid}';
    if (!Hive.isBoxOpen(boxName)) {
      Hive.openBox(boxName).then((_) => _processData());
    } else {
      _processData();
    }
  }

  void _processData() {
    final user = FirebaseAuth.instance.currentUser!;
    final box = Hive.box('transactions_${user.email ?? user.uid}');
    final rawData = box.get('transactions', defaultValue: []);
    spendingLimit = box.get('spending_limit', defaultValue: 0.0);
    
    if (rawData is List) {
      allTransactions = rawData.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        map['amount'] = map['amount'] is num
            ? (map['amount'] as num).toDouble()
            : double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0;
        map['isIncome'] = map['isIncome'] == true;
        map['category'] = map['category']?.toString() ?? 'Others';
        map['timestamp'] = map['timestamp'] is num
            ? (map['timestamp'] as num).toInt()
            : int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0;
        return map;
      }).toList();
    }

    final now = DateTime.now();

    todayDailyTxs.clear();
    yesterdayDailyTxs.clear();
    weeklyDaily.fillRange(0, 7, 0.0);
    monthlyDaily.fillRange(0, 31, 0.0);

    todayExpense = 0;
    yesterdayExpense = 0;
    weeklyExpense = 0;
    monthlyExpense = 0;
    
    dailyCat.clear();
    weeklyCat.clear();
    monthlyCat.clear();

    Set<int> daysWithTransactions = {};

    for (var tx in allTransactions) {
      if (tx['isIncome'] != isIncomeMode) continue;
      
      double amt = tx['amount'] as double;
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(tx['timestamp']);
      String cat = tx['category'];
      
      if (_isDailyOffset(dt, now, dailyOffset)) {
        todayExpense += amt;
        todayDailyTxs.add({"amt": amt, "time": dt, "cat": cat});
        dailyCat[cat] = (dailyCat[cat] ?? 0) + amt;
      } else if (_isDailyOffset(dt, now, dailyOffset + 1)) {
        yesterdayExpense += amt;
        yesterdayDailyTxs.add({"amt": amt, "time": dt, "cat": cat});
      }

      if (_isWeeklyOffset(dt, now, weeklyOffset)) {
        weeklyExpense += amt;
        weeklyDaily[dt.weekday - 1] += amt;
        weeklyCat[cat] = (weeklyCat[cat] ?? 0) + amt;
      }

      if (_isMonthlyOffset(dt, now, monthlyOffset)) {
        monthlyExpense += amt;
        monthlyDaily[dt.day - 1] += amt;
        monthlyCat[cat] = (monthlyCat[cat] ?? 0) + amt;
        if (amt > 0) daysWithTransactions.add(dt.day);
      }
    }

    int distinctActiveDays = daysWithTransactions.length;
    dailyAverage = monthlyExpense / (distinctActiveDays > 0 ? distinctActiveDays : 1);

    if (mounted) setState(() {});
  }

  bool _isDailyOffset(DateTime pt, DateTime now, int offset) {
    final target = now.subtract(Duration(days: offset));
    return pt.year == target.year && pt.month == target.month && pt.day == target.day;
  }

  bool _isWeeklyOffset(DateTime pt, DateTime now, int offset) {
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1 + (offset * 7)));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    return pt.isAfter(start.subtract(const Duration(seconds: 1))) && pt.isBefore(end.add(const Duration(seconds: 1)));
  }

  bool _isMonthlyOffset(DateTime pt, DateTime now, int offset) {
    int targetMonth = now.month - offset;
    int targetYear = now.year;
    while (targetMonth <= 0) {
      targetMonth += 12;
      targetYear -= 1;
    }
    return pt.year == targetYear && pt.month == targetMonth;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food': return const Color(0xFFF43F5E);
      case 'Travel': return const Color(0xFF3B82F6);
      case 'Shopping': return const Color(0xFF10B981);
      case 'Bills': return const Color(0xFFF59E0B);
      case 'Salary': return const Color(0xFF10B981);
      case 'Freelance': return const Color(0xFF8B5CF6);
      case 'Business': return const Color(0xFFF59E0B);
      case 'Gift': return const Color(0xFFF43F5E);
      case 'Refund': return const Color(0xFF3B82F6);
      case 'Others': return const Color(0xFF71717A);
      default: return const Color(0xFF71717A);
    }
  }

  String _getTopCategory(Map<String, double> catMap) {
    if (catMap.isEmpty) return "None";
    var largest = catMap.entries.reduce((a, b) => a.value > b.value ? a : b);
    return largest.key;
  }

  @override
  void dispose() {
    TransactionService.changeNotifier.removeListener(_loadData);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryAccent = const Color(0xFF06B6D4); 

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      floatingActionButton: const CrixyFloatingButton(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                   IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Analytics',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Qarume',
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _buildTopDropdown(
                    value: isIncomeMode ? 1 : 0,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("Expenses")),
                      DropdownMenuItem(value: 1, child: Text("Income")),
                    ],
                    onChanged: (val) {
                      setState(() {
                        isIncomeMode = val == 1;
                        _processData();
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                   Expanded(child: _buildSummaryCard("Daily", todayExpense, primaryAccent)),
                   const SizedBox(width: 16),
                   Expanded(child: _buildSummaryCard("Weekly", weeklyExpense, const Color(0xFFF43F5E))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                   Expanded(child: _buildSummaryCard("Monthly", monthlyExpense, const Color(0xFF10B981))),
                   const SizedBox(width: 16),
                   Expanded(child: _buildSummaryCard("Avg/Day", dailyAverage, const Color(0xFFF59E0B))),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white.withOpacity(0.08), 
                    borderRadius: BorderRadius.circular(20),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(fontFamily: 'Qarume', fontWeight: FontWeight.bold, fontSize: 15),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Qarume', fontWeight: FontWeight.normal, fontSize: 15),
                  tabs: const [
                    Tab(height: 40, text: "Daily"),
                    Tab(height: 40, text: "Weekly"),
                    Tab(height: 40, text: "Monthly"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                   _buildDailyAnalysis(primaryAccent),
                   _buildWeeklyAnalysis(),
                   _buildMonthlyAnalysis(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Qarume',
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "₹${amount.toStringAsFixed(0)}",
            style: const TextStyle(
              fontFamily: 'Qarume',
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeNavigator(int offset, String unit, Function(int) onChange) {
    String text;
    if (unit == "Day") {
      text = offset == 0 ? "Today" : offset == 1 ? "Yesterday" : "$offset Days Ago";
    } else if (unit == "Week") {
      text = offset == 0 ? "This Week" : offset == 1 ? "Last Week" : "$offset Weeks Ago";
    } else {
      text = offset == 0 ? "This Month" : offset == 1 ? "Last Month" : "$offset Months Ago";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => onChange(offset + 1),
            child: const Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 20),
          ),
          const SizedBox(width: 16),
          Text(text, style: const TextStyle(fontFamily: 'Qarume', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: offset == 0 ? null : () => onChange(offset - 1),
            child: Icon(Icons.chevron_right_rounded, color: offset == 0 ? Colors.transparent : Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }

  // ---- DAILY TAB ----
  Widget _buildDailyAnalysis(Color primaryAccent) {
    String diffText;
    if (yesterdayExpense == 0) {
      diffText = "No ${isIncomeMode ? 'income' : 'expenses'} the day prior";
    } else {
      double p = ((todayExpense - yesterdayExpense) / yesterdayExpense) * 100;
      if (p > 0) {
        diffText = "You tracked ${p.toStringAsFixed(0)}% more than the day prior";
      } else {
        diffText = "You tracked ${p.abs().toStringAsFixed(0)}% less than the day prior";
      }
    }

    double maxH = 10;
    if (spendingLimit > maxH && !isIncomeMode) maxH = spendingLimit;

    List<FlSpot> ySpots = [];
    List<FlSpot> tSpots = [];
    Map<double, double> yRawMap = {};
    Map<double, double> tRawMap = {};

    DateTime now = DateTime.now();

    // Map Exact Minutes for Yesterday
    Map<double, double> yConsolidated = {};
    for (var tx in yesterdayDailyTxs) {
        DateTime t = tx['time'];
        double amt = tx['amt'] as double;
        double x = t.hour + (t.minute / 60.0);
        x = double.parse(x.toStringAsFixed(4));
        yConsolidated[x] = (yConsolidated[x] ?? 0) + amt;
        yRawMap[x] = (yRawMap[x] ?? 0) + amt;
    }
    
    double yRun = 0;
    ySpots.add(const FlSpot(0, 0));
    var yKeys = yConsolidated.keys.toList()..sort();
    for (double x in yKeys) {
        yRun += yConsolidated[x]!;
        ySpots.add(FlSpot(x, yRun));
        if (yRun > maxH) maxH = yRun;
    }
    ySpots.add(FlSpot(23.99, yRun));

    // Map Exact Minutes for Today
    Map<double, double> tConsolidated = {};
    for(var tx in todayDailyTxs) {
        DateTime t = tx['time'];
        if (dailyOffset == 0 && t.isAfter(now)) continue;
        double amt = tx['amt'] as double;
        double x = t.hour + (t.minute / 60.0);
        x = double.parse(x.toStringAsFixed(4));
        tConsolidated[x] = (tConsolidated[x] ?? 0) + amt;
        tRawMap[x] = (tRawMap[x] ?? 0) + amt;
    }

    double tRun = 0;
    tSpots.add(const FlSpot(0, 0));
    var tKeys = tConsolidated.keys.toList()..sort();
    for (double x in tKeys) {
        tRun += tConsolidated[x]!;
        tSpots.add(FlSpot(x, tRun));
        if (tRun > maxH) maxH = tRun;
    }

    if (dailyOffset == 0) {
        double currentX = double.parse((now.hour + (now.minute / 60.0)).toStringAsFixed(4));
        if (!tConsolidated.containsKey(currentX)) {
           tSpots.add(FlSpot(currentX, tRun));
        }
    } else {
        if (!tConsolidated.containsKey(23.99)) {
           tSpots.add(FlSpot(23.99, tRun));
        }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildTimeNavigator(dailyOffset, "Day", (val) {
                setState(() => dailyOffset = val);
                _processData();
              }),
            ],
          ),
          const SizedBox(height: 12),
          Container(
             height: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                       "Cumulative",
                      style: TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 16),
                    ),
                    Row(
                      children: [
                        _buildLegend("Prev", const Color(0xFF3F3F46)),
                        const SizedBox(width: 8),
                        _buildLegend("Curr", primaryAccent),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 24,
                      minY: 0,
                      maxY: maxH * 1.2,
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              bool isToday = spot.barIndex == 1; // 0 is yesterday, 1 is today
                              double rx = double.parse(spot.x.toStringAsFixed(4));
                              double rawTx = isToday ? (tRawMap[rx] ?? 0) : (yRawMap[rx] ?? 0);
                              
                              int minSec = (spot.x * 60).toInt();
                              int hr = minSec ~/ 60;
                              int min = minSec % 60;
                              String minStr = min.toString().padLeft(2, '0');
                              String timeLabel = hr == 0 ? "12:$minStr AM" : hr < 12 ? "$hr:$minStr AM" : hr == 12 ? "12:$minStr PM" : "${hr - 12}:$minStr PM";
                              
                              return LineTooltipItem(
                                'Total: ₹${spot.y.toStringAsFixed(0)}\n',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Qarume'),
                                children: [
                                  TextSpan(text: '$timeLabel\n', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.normal)),
                                  if (rawTx > 0)
                                    TextSpan(
                                      text: 'Amt: ₹${rawTx.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: isIncomeMode ? const Color(0xFF10B981) : const Color(0xFFF43F5E), 
                                        fontSize: 11, 
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                ],
                              );
                            }).toList();
                          },
                        ),
                      ),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: (!isIncomeMode && spendingLimit > 0) ? [
                           HorizontalLine(
                              y: spendingLimit,
                              color: const Color(0xFFF43F5E).withOpacity(0.5),
                              strokeWidth: 2,
                              dashArray: [5, 5],
                           )
                        ] : [],
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [4, 4]),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              if (value == 0 || value == maxH * 1.2) return const SizedBox.shrink();
                              String text = value >= 1000 ? '${(value/1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0);
                              return SideTitleWidget(
                                meta: meta,
                                space: 4,
                                child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Qarume')),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 6,
                            getTitlesWidget: (value, meta) {
                              return SideTitleWidget(
                                meta: meta,
                                space: 8,
                                child: Text('${value.toInt()}:00', style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Qarume')),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: ySpots,
                          isCurved: false, // Straight segmented lines instead of bezier curves
                          color: const Color(0xFF3F3F46),
                          barWidth: 2, // thin rendering
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, data) => yRawMap.containsKey(double.parse(spot.x.toStringAsFixed(4))),
                          ),
                        ),
                        LineChartBarData(
                          spots: tSpots,
                          isCurved: false, // Straight segmented lines instead of bezier curves
                          gradient: LinearGradient(
                            colors: [primaryAccent, const Color(0xFF3B82F6)],
                          ),
                          barWidth: 3, // professional size
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, data) => tRawMap.containsKey(double.parse(spot.x.toStringAsFixed(4))),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                primaryAccent.withOpacity(0.4),
                                primaryAccent.withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildInsight(diffText, primaryAccent, Icons.insights),
          const SizedBox(height: 24),
          _buildPieChartSection("Daily Breakdown", dailyCat),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- WEEKLY TAB ----
  Widget _buildWeeklyAnalysis() {
    double maxW = 10;
    for(var v in weeklyDaily) { if(v > maxW) maxW = v; }
    
    int maxIndex = 0;
    for(int i = 0; i<7; i++){
      if(weeklyDaily[i] > weeklyDaily[maxIndex]) maxIndex = i;
    }
    
    List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    List<String> fullDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    
    String highestDayText = "${fullDays[maxIndex]} is your highest tracking day";
    if (weeklyExpense == 0) highestDayText = "No ${isIncomeMode ? 'income' : 'expenses'} this week";

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               _buildTimeNavigator(weeklyOffset, "Week", (val) {
                setState(() => weeklyOffset = val);
                _processData();
              }),
            ],
          ),
          const SizedBox(height: 12),
          Container(
             height: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tracking (Mon - Sun)",
                  style: TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      minY: 0,
                      maxY: maxW * 1.2,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '₹${rod.toY.toStringAsFixed(0)}',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Qarume'),
                            );
                          }
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              if (value == 0 || value == maxW * 1.2) return const SizedBox.shrink();
                              String text = value >= 1000 ? '${(value/1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0);
                              return SideTitleWidget(
                                meta: meta,
                                space: 4,
                                child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Qarume')),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              const style = TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Qarume');
                              return SideTitleWidget(meta: meta, space: 8, child: Text(days[value.toInt()][0], style: style));
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [4, 4]),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(7, (i) {
                        return _buildBarGroup(i, weeklyDaily[i], maxY: maxW * 1.2);
                      }),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 500),
                    swapAnimationCurve: Curves.easeInOut,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildInsight(highestDayText, const Color(0xFFF43F5E), Icons.trending_up),
          const SizedBox(height: 24),
          _buildPieChartSection("Weekly Breakdown", weeklyCat),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y, {required double maxY}) {
    double intensity = maxY > 0 ? (y / maxY) : 0;
    Color barColor = Color.lerp(const Color(0xFF10B981), const Color(0xFFF43F5E), intensity) ?? const Color(0xFF3F3F46);

    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          gradient: LinearGradient(
            colors: [barColor, barColor.withOpacity(0.7)],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
          width: 16,
          borderRadius: BorderRadius.zero,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: maxY <= 0 ? 10 : maxY,
            color: const Color(0xFF27272A),
          ),
        ),
      ],
    );
  }

  // ---- MONTHLY TAB ----
  Widget _buildMonthlyAnalysis() {
    String topCat = _getTopCategory(monthlyCat);
    String topCatText = monthlyExpense > 0 ? "$topCat is your top tracked category" : "No tracking yet this month";

    double maxM = 10;
    for (var v in monthlyDaily) if(v > maxM) maxM = v;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               _buildTimeNavigator(monthlyOffset, "Month", (val) {
                setState(() => monthlyOffset = val);
                _processData();
              }),
            ],
          ),
          const SizedBox(height: 12),
          Container(
             height: 260,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Monthly Trend",
                  style: TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxM * 1.2,
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              int day = spot.x.toInt();
                              return LineTooltipItem(
                                '₹${spot.y.toStringAsFixed(0)}\n',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Qarume'),
                                children: [
                                  TextSpan(text: 'Day $day', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.normal)),
                                ],
                              );
                            }).toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [4, 4]),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              if (value == 0 || value == maxM * 1.2) return const SizedBox.shrink();
                              String text = value >= 1000 ? '${(value/1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0);
                              return SideTitleWidget(
                                meta: meta,
                                space: 4,
                                child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Qarume')),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 5,
                            getTitlesWidget: (value, meta) {
                               if (value < 1 || value > 31) return const SizedBox.shrink();
                               return SideTitleWidget(
                                  meta: meta,
                                  space: 8,
                                  child: Text('${value.toInt()}', style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Qarume')),
                               );
                            }
                          )
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: monthlyDaily.asMap().entries.map((e) => FlSpot(e.key.toDouble() + 1, e.value)).toList(),
                          isCurved: true,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF34D399)],
                          ),
                          barWidth: 3, // Thinned line like daily
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF10B981).withOpacity(0.4),
                                const Color(0xFF10B981).withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          _buildPieChartSection("Monthly Breakdown", monthlyCat),
          const SizedBox(height: 16),

          _buildInsight(topCatText, const Color(0xFF10B981), Icons.category_rounded),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- PIE CHART AND HELPERS ---
  Widget _buildPieChartSection(String title, Map<String, double> categoryData) {
    if (categoryData.isEmpty) {
      return Container(
        height: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF27272A)),
        ),
        child: const Center(
          child: Text("No category data available", style: TextStyle(color: Colors.white54, fontFamily: 'Qarume')),
        ),
      );
    }
    
    double total = categoryData.values.fold(0.0, (sum, val) => sum + val);

    final sortedEntries = categoryData.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final List<double> radiiStack = [45, 40, 35, 30, 25];

    return Container(
      height: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text(
            title,
            style: const TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 30,
                      sections: sortedEntries.asMap().entries.map((e) {
                         int idx = e.key;
                         var entry = e.value;
                         double pct = (entry.value / total) * 100;
                         double r = idx < radiiStack.length ? radiiStack[idx] : 20.0;
                         return PieChartSectionData(
                           color: _getCategoryColor(entry.key),
                           value: entry.value,
                           title: '${pct.toStringAsFixed(0)}%',
                           radius: r,
                           titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Qarume'),
                         );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: sortedEntries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _buildLegend(e.key, _getCategoryColor(e.key), isFlexible: true),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      )
    );
  }

  Widget _buildTopDropdown({required int value, required List<DropdownMenuItem<int>> items, required Function(int?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(16),
          icon: const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Icon(Icons.unfold_more_rounded, color: Colors.white54, size: 16),
          ),
          dropdownColor: const Color(0xFF18181B),
          style: const TextStyle(fontFamily: 'Qarume', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildInsight(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'Qarume', color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String title, Color color, {bool isFlexible = false}) {
    Widget textWidget = Text(
      title,
      style: const TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 12),
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        isFlexible ? Flexible(child: textWidget) : textWidget,
      ],
    );
  }
}
