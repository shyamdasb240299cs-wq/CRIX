import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../models/chat_message.dart';
import '../services/crixy_service.dart';
import '../services/db_service.dart';
import '../services/hive_service.dart';
import '../services/transaction_service.dart';

class CrixyScreen extends StatefulWidget {
  const CrixyScreen({super.key});

  @override
  State<CrixyScreen> createState() => _CrixyScreenState();
}

class _CrixyScreenState extends State<CrixyScreen> {
  final CrixyService _crixyService = CrixyService();
  final HiveService _hiveService = HiveService();
  final DbService _dbService = DbService();
  final TransactionService _transactionService = TransactionService();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isResponding = false;
  bool _hasSeenIntro = false;
  bool _showChatUI = false;

  List<ChatMessage> _messages = [];

  final String _fullIntroText =
      "I'm Crixy, your personal wallet buddy.\n"
      "I can help you track spending, manage past transactions, and answer money questions in a simple way.\n"
      "You can ask me to add, edit, or delete transactions, or just chat about your wallet anytime.";

  String get _assistantPlannerPrompt => '''
You are Crixy, a highly intelligent financial AI assistant. You understand context deeply and respond with sophistication.

Always return one valid JSON object with exactly these top-level keys:
{
  "action": "chat" | "add_transaction" | "edit_transaction" | "delete_transaction" | "clarify",
  "reply": "friendly user-facing reply",
  "data": {}
}

Core Philosophy:
- Sound like a real, intelligent AI assistant - natural, warm, insightful.
- For transaction intent: EXTRACT CLEANLY. Never copy raw input as title.
- ENTITY DETECTION: If the user mentions a name (e.g., "hari", "shyam", "mom"), that is the TITLE.
- If they mention "shyam for eating burger", the title is just "shyam" or "shyam - burger".
- Strip everything like "for eating", "for buying", "100 rs", etc. from the title.
- Example: "add transaction in the name shyam for eating burger for 100 rs" -> title: "shyam", amount: 100, category: "Food"
- Example: "add transaction in the name hari for books 100 rs" -> title: "hari", amount: 100, category: "Others" (or "Business")

Extraction Rules for Transactions:
- Title: Extract the person, place, or core item. STOP before "for", "on", "at", "as".
- Category Inference: 
    - Food: burger, eating, food, restaurant, zomato.
    - Travel: bus, train, metro, uber.
- Date: Use relative dates.
- Type: Expense by default.

Action Contracts:
- chat: Reply naturally to any question. data = {}
- add_transaction: Extracted fields = {title, amount, type, category, date}
- edit_transaction: Target markers + changes
- delete_transaction: Target markers
- clarify: Ask specific follow-up.
''';

  String get _assistantReplyPrompt => '''
You are Crixy, an intelligent financial AI friend in their wallet app.

Personality:
- Sound like OpenAI's ChatGPT: thoughtful, warm, conversational, concise.
- Never robotic or overly formal. Be genuinely helpful and insightful.
- Adapt tone to context: friendly for casual questions, serious for financial concerns.

Response Strategy:
- Keep replies short: 1-4 sentences typically, unless depth is needed.
- Answer the question directly first, then offer one relevant insight or next step.
- Use the wallet context to give specific, personalized advice—not generic tips.
- Spot patterns: "I notice you spend a lot on Food lately" or "Your biggest category this month is Travel".
- Proactive help: "You're 75% through your budget. Want to track the rest closely?"

Financial Advice Examples:
- If they ask about spending: Analyze their actual data. "Your Food expenses are 35% of monthly spend. That's reasonable, but could cut 10% by meal planning."
- If they ask about saving: Reference their balance. "You've been saving well this month! You've set aside 40% of income."
- If they ask for general advice: Respond intelligently, backed by their real numbers where relevant.
- If they hit limits: Be supportive. "You're at your daily limit. How can I help you plan the rest of the week?"

Technical Notes:
- Never expose raw JSON, data structures, or internal logic.
- Don't dump the full transaction list—summarize smartly.
- Reference specific amounts and categories when possible.
- Keep advice actionable and realistic.
- If you don't know something, say so honestly but offer to help another way.
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCrixy();
    });
  }

  Future<void> _initCrixy() async {
    _hasSeenIntro = await _crixyService.hasSeenIntro();
    if (_hasSeenIntro) {
      _showChatUI = true;
      await _loadChats();
      await _maybeSendProactiveInsight();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      await _audioPlayer.play(AssetSource('voice/Crixy.mp3'));
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    await _playIntro();
  }

  Future<void> _playIntro() async {
    await _audioPlayer.play(AssetSource('voice/Crixy_intro.mp3'));
    await Future.delayed(const Duration(milliseconds: 4000));

    if (!mounted) return;

    setState(() {
      _showChatUI = true;
      _hasSeenIntro = true;
    });

    await _crixyService.setSeenIntro(true);
    await _sendBotMessage(_fullIntroText);
  }

  Future<void> _loadChats() async {
    final localMessages = await _hiveService.loadMessages();
    final remoteMessages = await _dbService.loadMessages();
    final mergedMessages = _mergeMessages(localMessages, remoteMessages);

    _messages = mergedMessages;

    for (final message in remoteMessages) {
      await _hiveService.saveMessage(message);
    }

    if (_messages.isEmpty) {
      await _sendBotMessage(
        "Hi, I'm Crixy. Ask me about your wallet or tell me a transaction to add, edit, or delete.",
      );
    } else {
      _scrollToBottom();
    }
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> localMessages,
    List<ChatMessage> remoteMessages,
  ) {
    final merged = <String, ChatMessage>{};

    for (final message in [...localMessages, ...remoteMessages]) {
      merged[message.id] = message;
    }

    final values = merged.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return values;
  }

  Future<void> _sendBotMessage(String text) async {
    final safeText = text.trim();
    if (safeText.isEmpty) return;

    final msg = ChatMessage(
      id: _nextMessageId(),
      message: safeText,
      isUser: false,
      timestamp: DateTime.now(),
    );
    await _saveAndDisplayMsg(msg);
  }

  Future<void> _handleUserSubmit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isResponding) return;

    _msgController.clear();

    final userMsg = ChatMessage(
      id: _nextMessageId(),
      message: trimmed,
      isUser: true,
      timestamp: DateTime.now(),
    );
    await _saveAndDisplayMsg(userMsg);

    if (!mounted) return;
    setState(() {
      _isResponding = true;
    });

    try {
      final plan = await _getAssistantPlan(trimmed);
      final reply = await _executeAssistantPlan(plan, trimmed);
      await _sendBotMessage(reply);
    } catch (e) {
      debugPrint('CRIXY_REPLY_ERROR: $e');
      await _sendBotMessage(
        "I couldn't process that clearly just now. Try saying the transaction title, amount, and date in one message.",
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResponding = false;
        });
      }
    }
  }

  Future<_AssistantPlan> _getAssistantPlan(String input) async {
    try {
      final apiKey = dotenv.env['OPENROUTER_API_KEY']?.trim() ?? '';
      if (apiKey.isEmpty) {
        return _buildOfflinePlan(input);
      }

      final walletContext = await _buildWalletContext();
      final historyFeed = _buildRecentConversationFeed(input);
      final model = (dotenv.env['OPENROUTER_MODEL']?.trim().isNotEmpty ?? false)
          ? dotenv.env['OPENROUTER_MODEL']!.trim()
          : 'openai/gpt-4o-mini';

      final rawContent = await _requestOpenRouterCompletion(
        model: model,
        temperature: 0.2,
        maxTokens: 380,
        messages: [
          {'role': 'system', 'content': _assistantPlannerPrompt},
          {'role': 'system', 'content': walletContext},
          ...historyFeed,
          {'role': 'user', 'content': input},
        ],
      );
      if (rawContent.trim().isEmpty) {
        throw const FormatException('Empty AI response');
      }

      return _parseAssistantPlan(rawContent);
    } catch (e) {
      debugPrint('CRIXY_AI_FALLBACK: $e');
      return _buildOfflinePlan(input, error: e);
    }
  }

  Future<String> _buildWalletContext() async {
    final transactions = await _transactionService.loadTransactions();
    final settingsBox = await _openUserTransactionBox();
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = DateFormat('yyyy-MM').format(now);
    final weekStart = _startOfWeek(now);
    final spendingLimit =
        (settingsBox?.get('spending_limit', defaultValue: 0.0) as num?)
            ?.toDouble() ??
        0.0;
    final isLimitTodayOnly =
        settingsBox?.get('limit_today_only', defaultValue: true) == true;

    var todayExpense = 0.0;
    var todayIncome = 0.0;
    var weekExpense = 0.0;
    var weekIncome = 0.0;
    var monthExpense = 0.0;
    var monthIncome = 0.0;
    final expenseByCategory = <String, double>{};

    for (final tx in transactions) {
      final isIncome = tx['isIncome'] == true;
      final amount = tx['amount'] as double? ?? 0.0;
      final timestamp = tx['timestamp'] as int? ?? 0;
      final dateKey = tx['date']?.toString() ?? '';
      final moment = timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : now;

      if (dateKey == todayKey) {
        if (isIncome) {
          todayIncome += amount;
        } else {
          todayExpense += amount;
        }
      }

      if (!moment.isBefore(weekStart)) {
        if (isIncome) {
          weekIncome += amount;
        } else {
          weekExpense += amount;
        }
      }

      if (dateKey.startsWith(monthKey)) {
        if (isIncome) {
          monthIncome += amount;
        } else {
          monthExpense += amount;
          final category = tx['category']?.toString() ?? 'Others';
          expenseByCategory[category] =
              (expenseByCategory[category] ?? 0) + amount;
        }
      }
    }

    // Calculate top 3 categories for analysis
    final sortedCategories = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var topCategory = 'None';
    var topCategoryAmount = 0.0;
    var secondTopCategory = '';
    var secondTopAmount = 0.0;

    if (sortedCategories.isNotEmpty) {
      topCategory = sortedCategories[0].key;
      topCategoryAmount = sortedCategories[0].value;
    }
    if (sortedCategories.length > 1) {
      secondTopCategory = sortedCategories[1].key;
      secondTopAmount = sortedCategories[1].value;
    }

    final trackedSpend = isLimitTodayOnly ? todayExpense : monthExpense;
    final limitPeriod = isLimitTodayOnly ? 'today' : 'this month';
    final limitLeft = spendingLimit > 0 ? spendingLimit - trackedSpend : 0.0;
    final savingsDelta = monthIncome - monthExpense;

    // Calculate spending health insights
    String healthInsight = '';
    if (spendingLimit > 0) {
      final limitUsagePercent = (trackedSpend / spendingLimit) * 100;
      if (limitUsagePercent >= 100) {
        healthInsight =
            'You have EXCEEDED your $limitPeriod limit by Rs ${TransactionService.formatAmount(trackedSpend - spendingLimit)}. Be cautious with new expenses.';
      } else if (limitUsagePercent >= 85) {
        healthInsight =
            'You are using ${limitUsagePercent.toStringAsFixed(0)}% of your $limitPeriod budget. Only Rs ${TransactionService.formatAmount(limitLeft)} remains.';
      } else if (limitUsagePercent >= 50) {
        healthInsight =
            'You are halfway through your $limitPeriod budget. Good pace so far.';
      }
    }

    // Expense-to-income ratio
    String balanceInsight = '';
    if (monthIncome > 0) {
      final expenseRatio = (monthExpense / monthIncome) * 100;
      if (expenseRatio > 90) {
        balanceInsight =
            'Caution: You are spending ${expenseRatio.toStringAsFixed(0)}% of your income this month. You are saving very little.';
      } else if (expenseRatio > 70) {
        balanceInsight =
            'You are spending ${expenseRatio.toStringAsFixed(0)}% of your income. Consider cutting discretionary expenses to save more.';
      } else if (expenseRatio < 40) {
        balanceInsight =
            'Great! You are only spending ${expenseRatio.toStringAsFixed(0)}% of income. You have healthy savings.';
      }
    }

    return '''
CURRENT DATE: ${DateFormat('yyyy-MM-dd').format(now)}

WALLET SUMMARY:
- total transactions logged: ${transactions.length}
- today expense: Rs ${TransactionService.formatAmount(todayExpense)}
- today income: Rs ${TransactionService.formatAmount(todayIncome)}
- this week expense: Rs ${TransactionService.formatAmount(weekExpense)}
- this week income: Rs ${TransactionService.formatAmount(weekIncome)}
- this month expense: Rs ${TransactionService.formatAmount(monthExpense)}
- this month income: Rs ${TransactionService.formatAmount(monthIncome)}
- net this month (savings): Rs ${TransactionService.formatAmount(savingsDelta)}

SPENDING LIMIT:
- limit set: ${spendingLimit > 0 ? 'Rs ${TransactionService.formatAmount(spendingLimit)} for $limitPeriod' : 'not set'}
- tracked against limit: Rs ${TransactionService.formatAmount(trackedSpend)}
- remaining: ${spendingLimit > 0 ? 'Rs ${TransactionService.formatAmount(limitLeft)}' : 'not applicable'}

EXPENSE BREAKDOWN (This Month):
- top category: $topCategory at Rs ${TransactionService.formatAmount(topCategoryAmount)} (${(topCategoryAmount > 0 && monthExpense > 0 ? ((topCategoryAmount / monthExpense) * 100).toStringAsFixed(0) : '0')}% of spending)
${secondTopCategory.isNotEmpty ? '- second: $secondTopCategory at Rs ${TransactionService.formatAmount(secondTopAmount)}' : ''}

FINANCIAL INSIGHTS & ADVICE:
${healthInsight.isNotEmpty ? '• BUDGET STATUS: $healthInsight' : ''}
${balanceInsight.isNotEmpty ? '• INCOME RATIO: $balanceInsight' : ''}

CONTEXT FOR RESPONSES:
- If user asks about spending, reference their actual top categories and suggest adjustments.
- If they are approaching or over limit, remind them proactively.
- If savings are good, acknowledge and encourage.
- If spending patterns are unhealthy, offer specific recommendations.
- Use this data to give personalized financial advice, not generic tips.

${_transactionService.buildRecentTransactionsContext(transactions)}
''';
  }

  List<Map<String, String>> _buildRecentConversationFeed(String currentInput) {
    var history = List<ChatMessage>.from(_messages);
    if (history.isNotEmpty &&
        history.last.isUser &&
        history.last.message.trim() == currentInput.trim()) {
      history = history.sublist(0, history.length - 1);
    }

    final start = math.max(0, history.length - 12);
    final recent = history.sublist(start);

    return recent
        .map(
          (msg) => {
            'role': msg.isUser ? 'user' : 'assistant',
            'content': msg.message,
          },
        )
        .toList();
  }

  Future<String> _executeAssistantPlan(
    _AssistantPlan plan,
    String originalInput,
  ) async {
    switch (plan.action) {
      case 'add_transaction':
        return _handleAddTransaction(plan.data, originalInput);
      case 'edit_transaction':
        return _handleEditTransaction(plan.data, originalInput);
      case 'delete_transaction':
        return _handleDeleteTransaction(plan.data, originalInput);
      case 'clarify':
        return _safeReply(
          plan.reply,
          fallback:
              "Tell me exactly which transaction you mean, and I'll take care of it.",
        );
      case 'chat':
      default:
        return _buildSmartChatReply(plan.reply, originalInput);
    }
  }

  Future<String> _handleAddTransaction(
    Map<String, dynamic> data,
    String originalInput,
  ) async {
    final normalized = _mergeAddTransactionData(data, originalInput);
    final title = _readFirstString(normalized, const ['title', 'name']);
    final amount = _readAmount(normalized['amount']);
    final isIncome = _readTransactionType(
      normalized['type'] ?? normalized['isIncome'],
    );
    final date = _readDate(normalized['date']);
    final category = _readFirstString(normalized, const ['category']);

    if (title.isEmpty || amount == null || amount <= 0 || isIncome == null) {
      return "I can add that for you. Just tell me the title, amount, and whether it was income or expense.";
    }

    final transaction = await _transactionService.addTransaction(
      name: title,
      amount: amount,
      isIncome: isIncome,
      category: category,
      date: date ?? DateTime.now(),
    );

    final verb = transaction['isIncome'] == true ? 'income' : 'expense';
    final chatDate = _formatTransactionDate(transaction['date']?.toString());
    return "Done. I added a $verb of Rs ${TransactionService.formatAmount(transaction['amount'] as double)} for ${transaction['name']} on $chatDate.";
  }

  Future<String> _buildSmartChatReply(
    String draftedReply,
    String originalInput,
  ) async {
    final apiKey = dotenv.env['OPENROUTER_API_KEY']?.trim() ?? '';

    // Check if this is a transaction history query - handle locally first
    if (_isTransactionHistoryQuery(originalInput)) {
      final historyReply = await _handleTransactionHistoryQuery(originalInput);
      if (historyReply.isNotEmpty) {
        return historyReply;
      }
    }

    // Check for financial advice queries
    if (_isFinancialAdviceQuery(originalInput)) {
      final adviceReply = await _generatePersonalizedFinancialAdvice();
      if (adviceReply.isNotEmpty) {
        return adviceReply;
      }
    }

    // Check for category spending queries
    if (_isCategorySpendingQuery(originalInput)) {
      final categoryReply = await _handleCategorySpendingQuery(originalInput);
      if (categoryReply.isNotEmpty) {
        return categoryReply;
      }
    }

    final fallback = _safeReply(
      draftedReply,
      fallback:
          "I'm here to help with your wallet. You can ask a question or tell me a transaction to manage.",
    );
    if (apiKey.isEmpty) return fallback;

    try {
      final walletContext = await _buildWalletContext();
      final historyFeed = _buildRecentConversationFeed(originalInput);
      final model = (dotenv.env['OPENROUTER_MODEL']?.trim().isNotEmpty ?? false)
          ? dotenv.env['OPENROUTER_MODEL']!.trim()
          : 'openai/gpt-4o-mini';

      final content = await _requestOpenRouterCompletion(
        model: model,
        temperature: 0.7,
        maxTokens: 280,
        messages: [
          {'role': 'system', 'content': _assistantReplyPrompt},
          {'role': 'system', 'content': walletContext},
          ...historyFeed,
          {'role': 'user', 'content': originalInput},
        ],
      );
      return _safeReply(content, fallback: fallback);
    } catch (e) {
      debugPrint('CRIXY_CHAT_REPLY_FALLBACK: $e');
      return fallback;
    }
  }

  bool _isTransactionHistoryQuery(String input) {
    final lower = input.toLowerCase();
    final hasHistoryKeyword = [
      'transaction',
      'history',
      'detail',
      'list',
      'show',
      'give me',
      'tell me',
      'total',
      'sum',
      'spent',
      'expense',
    ].any(lower.contains);

    if (!hasHistoryKeyword) return false;

    // Must also have a time period indicator
    final hasTimeIndicator = [
      'last.*day',
      'past.*day',
      'week',
      'month',
      'today',
      'yesterday',
      'day',
      'two day',
      'how much',
    ].any((pattern) => RegExp(pattern, caseSensitive: false).hasMatch(lower));

    return hasTimeIndicator;
  }

  bool _isFinancialAdviceQuery(String input) {
    final lower = input.toLowerCase();
    return [
          'advice',
          'analyze my',
          'analysis',
          'suggest',
          'recommend',
          'financial',
          'personal',
        ].any(lower.contains) &&
        [
          'transaction',
          'spending',
          'money',
          'financial',
          'budget',
          'spend',
        ].any(lower.contains);
  }

  bool _isCategorySpendingQuery(String input) {
    final lower = input.toLowerCase();
    return [
          'which',
          'field',
          'category',
          'where',
          'most',
          'highest',
          'spent',
        ].any(lower.contains) &&
        [
          'money',
          'spent',
          'spending',
          'cost',
          'expense',
          'category',
          'field',
        ].any(lower.contains);
  }

  Future<String> _handleTransactionHistoryQuery(String input) async {
    try {
      final transactions = await _transactionService.loadTransactions();
      final lower = input.toLowerCase();
      final now = DateTime.now();

      // Determine date range
      DateTime startDate = now;
      DateTime endDate = now;
      String periodLabel = 'today';

      if (['last.*2.*day', 'past.*2.*day', '2.*day', 'two.*day'].any(
        (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(lower),
      )) {
        startDate = now.subtract(const Duration(days: 2));
        periodLabel = 'last 2 days';
      } else if (['last.*week', 'past week', 'this week', 'week'].any(
        (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(lower),
      )) {
        startDate = _startOfWeek(now);
        endDate = now;
        periodLabel = 'this week';
      } else if (['last.*month', 'past month', 'this month', 'month'].any(
        (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(lower),
      )) {
        startDate = DateTime(now.year, now.month, 1);
        endDate = now;
        periodLabel = 'this month';
      } else if (['today'].any(lower.contains)) {
        startDate = DateTime(now.year, now.month, now.day);
        endDate = now;
        periodLabel = 'today';
      } else if (['yesterday'].any(lower.contains)) {
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = yesterday
            .add(const Duration(days: 1))
            .subtract(const Duration(seconds: 1));
        periodLabel = 'yesterday';
      }

      // Filter transactions for the period
      final filtered = transactions.where((tx) {
        final dateKey = tx['date']?.toString() ?? '';
        final dateTime = DateTime.tryParse(dateKey) ?? now;
        return !dateTime.isBefore(startDate) && !dateTime.isAfter(endDate);
      }).toList();

      if (filtered.isEmpty) {
        return "You don't have any transactions for $periodLabel.";
      }

      // Calculate summaries
      double totalExpense = 0;
      double totalIncome = 0;
      final categoryTotals = <String, double>{};
      final transactionsList = <String>[];

      for (final tx in filtered) {
        final amount = tx['amount'] as double? ?? 0.0;
        final name = tx['name']?.toString() ?? 'Unknown';
        final category = tx['category']?.toString() ?? 'Others';
        final isIncome = tx['isIncome'] == true;
        final date = tx['date']?.toString() ?? '';

        if (isIncome) {
          totalIncome += amount;
        } else {
          totalExpense += amount;
          categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        }

        final typeLabel = isIncome ? '💰' : '💸';
        transactionsList.add(
          '$typeLabel $name - Rs ${TransactionService.formatAmount(amount)} ($category) [$date]',
        );
      }

      // Build response
      final buffer = StringBuffer();
      buffer.writeln('📊 Transactions for $periodLabel\n');

      // Show all transactions
      for (final tx in transactionsList) {
        buffer.writeln(tx);
      }

      buffer.writeln('\n📈 Summary:');
      buffer.writeln(
        'Total Expense: Rs ${TransactionService.formatAmount(totalExpense)}',
      );
      if (totalIncome > 0) {
        buffer.writeln(
          'Total Income: Rs ${TransactionService.formatAmount(totalIncome)}',
        );
      }
      buffer.writeln(
        'Net: Rs ${TransactionService.formatAmount(totalIncome - totalExpense)}',
      );

      // Show category breakdown
      if (categoryTotals.isNotEmpty) {
        buffer.writeln('\n📍 Category Breakdown:');
        final sorted = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final entry in sorted) {
          final percent = (entry.value / totalExpense * 100).toStringAsFixed(1);
          buffer.writeln(
            '  • ${entry.key}: Rs ${TransactionService.formatAmount(entry.value)} ($percent%)',
          );
        }
      }

      // Add spending reduction advice if applicable
      if (categoryTotals.isNotEmpty &&
          ['reduce', 'how can i', 'how do i', 'cut'].any(
            (keyword) => RegExp(keyword, caseSensitive: false).hasMatch(input),
          )) {
        buffer.writeln('\n💡 Tips to Reduce Spending Next $periodLabel:');
        final topCategory = categoryTotals.entries.first;
        final topPercent = (topCategory.value / totalExpense * 100)
            .toStringAsFixed(0);
        buffer.writeln(
          '  • Your highest spending is ${topCategory.key} ($topPercent% of budget)',
        );

        if (topCategory.key == 'Food') {
          buffer.writeln('    → Try meal planning or cooking at home 🍳');
        } else if (topCategory.key == 'Travel') {
          buffer.writeln('    → Combine trips or use public transport 🚌');
        } else if (topCategory.key == 'Shopping') {
          buffer.writeln('    → Avoid impulse purchases, make a list 📝');
        } else if (topCategory.key == 'Bills') {
          buffer.writeln(
            '    → Review subscriptions and cancel unused ones 🔍',
          );
        } else if (topCategory.key == 'Entertainment') {
          buffer.writeln('    → Set a monthly entertainment budget 🎬');
        } else if (topCategory.key == 'Healthcare') {
          buffer.writeln(
            '    → Compare prices for medicines and treatments 💊',
          );
        } else {
          buffer.writeln(
            '    → Review this category and find savings opportunities',
          );
        }

        if (categoryTotals.length > 1) {
          final secondHighest = categoryTotals.entries.toList()[1];
          buffer.writeln(
            '  • Second highest: ${secondHighest.key} (Rs ${TransactionService.formatAmount(secondHighest.value)})',
          );
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('TRANSACTION_HISTORY_ERROR: $e');
      return '';
    }
  }

  Future<String> _generatePersonalizedFinancialAdvice() async {
    try {
      final transactions = await _transactionService.loadTransactions();
      if (transactions.isEmpty) {
        return 'You haven\'t added any transactions yet! Start tracking your expenses and I can give you personalized advice. 💰';
      }

      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);
      final monthlyTransactions = transactions
          .where((tx) => tx['date']?.toString().startsWith(monthKey) ?? false)
          .toList();

      double totalExpense = 0;
      double totalIncome = 0;
      final categoryTotals = <String, double>{};

      for (final tx in monthlyTransactions) {
        final amount = tx['amount'] as double? ?? 0.0;
        final isIncome = tx['isIncome'] == true;
        final category = tx['category']?.toString() ?? 'Others';

        if (isIncome) {
          totalIncome += amount;
        } else {
          totalExpense += amount;
          categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        }
      }

      if (totalExpense == 0) {
        return 'No expense data available for this month yet. Start adding transactions to get personalized advice! 📊';
      }

      final buffer = StringBuffer();
      buffer.writeln('💰 Your Financial Analysis for $monthKey\n');

      final savingsRate = totalIncome > 0
          ? ((totalIncome - totalExpense) / totalIncome * 100).toStringAsFixed(
              1,
            )
          : '0.0';

      buffer.writeln('📊 This Month Overview:');
      buffer.writeln(
        '  • Income: Rs ${TransactionService.formatAmount(totalIncome)}',
      );
      buffer.writeln(
        '  • Expenses: Rs ${TransactionService.formatAmount(totalExpense)}',
      );
      buffer.writeln(
        '  • Net Savings: Rs ${TransactionService.formatAmount(totalIncome - totalExpense)}',
      );
      if (totalIncome > 0) {
        buffer.writeln('  • Savings Rate: $savingsRate%');
      }

      if (categoryTotals.isNotEmpty) {
        buffer.writeln('\n💡 Spending Insights:');
        final sorted = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (sorted.isNotEmpty) {
          final topSpending = sorted.first;
          final topPercent = (topSpending.value / totalExpense * 100)
              .toStringAsFixed(0);
          buffer.writeln(
            '  • You spent most on ${topSpending.key} ($topPercent% - Rs ${TransactionService.formatAmount(topSpending.value)})',
          );

          if (double.parse(topPercent) > 50) {
            buffer.writeln(
              '    ⚠️ This is quite high! Consider budgeting this category.',
            );
          }

          if (sorted.length > 1) {
            buffer.writeln('  • Top 3 categories:');
            for (var i = 0; i < sorted.length && i < 3; i++) {
              final entry = sorted[i];
              final percent = (entry.value / totalExpense * 100)
                  .toStringAsFixed(1);
              buffer.writeln(
                '    ${i + 1}. ${entry.key}: Rs ${TransactionService.formatAmount(entry.value)} ($percent%)',
              );
            }
          }
        }
      }

      buffer.writeln('\n🎯 Recommendations:');
      if (totalExpense > (totalIncome * 0.9) && totalIncome > 0) {
        buffer.writeln(
          '  • You\'re spending 90% or more of your income - try to reduce expenses',
        );
      } else if (totalExpense < (totalIncome * 0.5) && totalIncome > 0) {
        buffer.writeln(
          '  • Great! You\'re saving more than 50% - keep up the good work! 🌟',
        );
      }

      final highestCategory = categoryTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (highestCategory.isNotEmpty) {
        final category = highestCategory.first.key;
        if (category == 'Food' && highestCategory.first.value > 5000) {
          buffer.writeln(
            '  • Consider meal planning to reduce food expenses 🍳',
          );
        }
        if (category == 'Entertainment' && highestCategory.first.value > 3000) {
          buffer.writeln('  • Set limits on entertainment spending 🎬');
        }
        if (category == 'Shopping' && highestCategory.first.value > 4000) {
          buffer.writeln(
            '  • Make a list before shopping to avoid impulse purchases 📝',
          );
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('FINANCIAL_ADVICE_ERROR: $e');
      return 'Unable to generate financial advice at this time. Please try again later.';
    }
  }

  Future<String> _handleCategorySpendingQuery(String input) async {
    try {
      final transactions = await _transactionService.loadTransactions();
      if (transactions.isEmpty) {
        return 'You haven\'t added any transactions yet! Start tracking to see where you spend the most. 📊';
      }

      final lower = input.toLowerCase();
      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);

      // Filter transactions for this month
      final monthlyTransactions = transactions.where((tx) {
        final date = tx['date']?.toString() ?? '';
        return date.startsWith(monthKey) && tx['isIncome'] != true;
      }).toList();

      if (monthlyTransactions.isEmpty) {
        return 'No expense data for this month yet. Add some transactions to see your spending breakdown! 📊';
      }

      // Calculate spending by category
      final categoryTotals = <String, double>{};
      for (final tx in monthlyTransactions) {
        final amount = tx['amount'] as double? ?? 0.0;
        final category = tx['category']?.toString() ?? 'Others';
        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
      }

      if (categoryTotals.isEmpty) {
        return 'No spending data available. 📊';
      }

      // Sort by highest spending
      final sorted = categoryTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final buffer = StringBuffer();
      buffer.writeln('💰 Your Spending Breakdown for $monthKey\n');

      final topSpending = sorted.first;
      final totalExpense = categoryTotals.values.fold(
        0.0,
        (sum, val) => sum + val,
      );
      final topPercent = (topSpending.value / totalExpense * 100)
          .toStringAsFixed(1);

      buffer.writeln('📊 You spent the most on: ${topSpending.key}');
      buffer.writeln(
        '   Amount: Rs ${TransactionService.formatAmount(topSpending.value)}',
      );
      buffer.writeln('   Percentage: $topPercent% of total spending\n');

      buffer.writeln('📈 Full Category Breakdown:');
      for (var i = 0; i < sorted.length; i++) {
        final entry = sorted[i];
        final percent = (entry.value / totalExpense * 100).toStringAsFixed(1);
        buffer.writeln(
          '   ${i + 1}. ${entry.key}: Rs ${TransactionService.formatAmount(entry.value)} ($percent%)',
        );
      }

      buffer.writeln(
        '\n💡 Total Monthly Spending: Rs ${TransactionService.formatAmount(totalExpense)}',
      );

      return buffer.toString();
    } catch (e) {
      debugPrint('CATEGORY_SPENDING_ERROR: $e');
      return 'Unable to calculate category spending. Please try again later.';
    }
  }

  Future<String> _requestOpenRouterCompletion({
    required String model,
    required double temperature,
    required int maxTokens,
    required List<Map<String, String>> messages,
  }) async {
    final apiKey = dotenv.env['OPENROUTER_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const HttpException('Missing OpenRouter API key');
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final request = await client.postUrl(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('HTTP-Referer', 'https://wallet-app.local');
      request.headers.set('X-Title', 'Wallet App Crixy');

      final payload = jsonEncode({
        'model': model,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'messages': messages,
      });

      request.add(utf8.encode(payload));

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final responseBody = await response.transform(utf8.decoder).join();
      debugPrint('CRIXY_AI_RAW: $responseBody');

      if (response.statusCode != 200) {
        throw HttpException('OpenRouter error ${response.statusCode}');
      }

      final decoded = jsonDecode(responseBody);
      return decoded['choices']?[0]?['message']?['content']?.toString() ?? '';
    } finally {
      client?.close(force: true);
    }
  }

  Future<String> _handleDeleteTransaction(
    Map<String, dynamic> data,
    String originalInput,
  ) async {
    final target = _extractTargetData(data);
    final candidates = await _findTargetCandidates(
      target,
      originalInput: originalInput,
    );

    if (candidates.isEmpty) {
      return "I couldn't find that transaction yet. Tell me its title, amount, or date and I'll try again.";
    }

    if (_shouldClarifyTarget(target, candidates)) {
      return _buildClarificationReply(
        actionWord: 'delete',
        candidates: candidates,
      );
    }

    final transaction = candidates.first;
    final deleted = await _transactionService.deleteTransaction(
      transaction['id'].toString(),
    );

    if (!deleted) {
      return "I found a match, but I couldn't delete it just now. Please try once more.";
    }

    return "Done. I deleted ${_transactionService.describeTransaction(transaction)}.";
  }

  Future<String> _handleEditTransaction(
    Map<String, dynamic> data,
    String originalInput,
  ) async {
    final target = _extractTargetData(data);
    final changes = _extractChangeData(data);

    if (changes.isEmpty) {
      return "Tell me what you want to change about that transaction, like the amount, title, category, or date.";
    }

    final candidates = await _findTargetCandidates(
      target,
      originalInput: originalInput,
    );

    if (candidates.isEmpty) {
      return "I couldn't match that transaction yet. Tell me its title, amount, or date, and what should change.";
    }

    if (_shouldClarifyTarget(target, candidates)) {
      return _buildClarificationReply(
        actionWord: 'edit',
        candidates: candidates,
      );
    }

    final transaction = candidates.first;
    final updated = await _transactionService.updateTransaction(
      id: transaction['id'].toString(),
      name: _readFirstString(changes, const ['title', 'name']).isEmpty
          ? null
          : _readFirstString(changes, const ['title', 'name']),
      amount: _readAmount(changes['amount']),
      isIncome: _readTransactionType(changes['type'] ?? changes['isIncome']),
      category: _readFirstString(changes, const ['category']).isEmpty
          ? null
          : _readFirstString(changes, const ['category']),
      date: _readDate(changes['date']),
    );

    if (updated == null) {
      return "I found the transaction, but I couldn't update it. Try again with the new value you want.";
    }

    return "Done. I updated it to ${_transactionService.describeTransaction(updated)}.";
  }

  Future<List<Map<String, dynamic>>> _findTargetCandidates(
    Map<String, dynamic> target, {
    required String originalInput,
  }) async {
    return _transactionService.findCandidateTransactions(
      id: _readFirstString(target, const ['id']),
      title: _readFirstString(target, const ['title', 'name']),
      amount: _readAmount(target['amount']),
      date: _readDate(target['date']),
      isIncome: _readTransactionType(target['type'] ?? target['isIncome']),
      category: _readFirstString(target, const ['category']),
      userText: originalInput,
      limit: 3,
    );
  }

  bool _shouldClarifyTarget(
    Map<String, dynamic> target,
    List<Map<String, dynamic>> candidates,
  ) {
    if (candidates.isEmpty) return false;
    if (_readFirstString(target, const ['id']).isNotEmpty) return false;
    if (candidates.length == 1) return false;
    return _countTargetHints(target) < 2;
  }

  int _countTargetHints(Map<String, dynamic> target) {
    var count = 0;
    if (_readFirstString(target, const ['id']).isNotEmpty) count++;
    if (_readFirstString(target, const ['title', 'name']).isNotEmpty) count++;
    if (_readAmount(target['amount']) != null) count++;
    if (_readDate(target['date']) != null) count++;
    if (_readTransactionType(target['type'] ?? target['isIncome']) != null) {
      count++;
    }
    if (_readFirstString(target, const ['category']).isNotEmpty) count++;
    return count;
  }

  String _buildClarificationReply({
    required String actionWord,
    required List<Map<String, dynamic>> candidates,
  }) {
    final buffer = StringBuffer(
      "I found a few close matches. Which one should I $actionWord?\n",
    );

    for (var i = 0; i < candidates.length; i++) {
      buffer.writeln(
        '${i + 1}. ${_transactionService.describeTransaction(candidates[i])}',
      );
    }

    return buffer.toString().trim();
  }

  Map<String, dynamic> _extractTargetData(Map<String, dynamic> data) {
    final target = data['target'];
    if (target is Map) {
      return Map<String, dynamic>.from(target);
    }

    final extracted = <String, dynamic>{};
    for (final key in [
      'id',
      'title',
      'name',
      'amount',
      'type',
      'isIncome',
      'category',
      'date',
    ]) {
      if (data.containsKey(key)) {
        extracted[key] = data[key];
      }
    }
    return extracted;
  }

  Map<String, dynamic> _extractChangeData(Map<String, dynamic> data) {
    final changes = data['changes'];
    if (changes is Map) {
      return Map<String, dynamic>.from(changes);
    }

    final extracted = <String, dynamic>{};
    const directKeys = [
      'title',
      'name',
      'amount',
      'type',
      'isIncome',
      'category',
      'date',
    ];

    for (final key in directKeys) {
      final newKey = 'new_$key';
      if (data.containsKey(newKey)) {
        extracted[key] = data[newKey];
      }
    }

    return extracted;
  }

  _AssistantPlan _parseAssistantPlan(String raw) {
    try {
      final jsonText = _extractJsonObject(raw);
      if (jsonText == null) {
        return _AssistantPlan.chat(
          _sanitizePlainReply(
            raw,
            fallback:
                "I didn't catch that clearly. Tell me your wallet question or the transaction you want me to manage.",
          ),
        );
      }

      final repaired = jsonText.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
      final decoded = jsonDecode(repaired);
      if (decoded is Map<String, dynamic>) {
        return _AssistantPlan.fromJson(decoded);
      }
      if (decoded is Map) {
        return _AssistantPlan.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('CRIXY_PLAN_PARSE_ERROR: $e');
    }

    return _AssistantPlan.chat(
      _sanitizePlainReply(
        raw,
        fallback:
            "I couldn't format that clearly. Please try again in a simple sentence.",
      ),
    );
  }

  String? _extractJsonObject(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();

    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
      return null;
    }

    return cleaned.substring(firstBrace, lastBrace + 1);
  }

  _AssistantPlan _buildOfflinePlan(String input, {Object? error}) {
    final lower = input.toLowerCase();

    if (_looksLikeAddIntent(lower)) {
      final extracted = _extractStructuredTransaction(input);
      final amount =
          _readAmount(extracted['amount']) ?? _extractFirstAmount(input);
      final title = _readFirstString(extracted, const ['title', 'name']).isEmpty
          ? _guessOfflineTitle(input)
          : _readFirstString(extracted, const ['title', 'name']);
      final isIncome =
          _readTransactionType(extracted['type']) ??
          _readTransactionType(extracted['isIncome']) ??
          _looksLikeIncomeIntent(lower);
      final date =
          _readDate(extracted['date']) ??
          _extractDateFromInput(input) ??
          DateTime.now();

      if (amount != null && title.isNotEmpty) {
        return _AssistantPlan(
          action: 'add_transaction',
          reply: '',
          data: {
            'title': title,
            'amount': amount,
            'type': isIncome ? 'income' : 'expense',
            'category': _readFirstString(extracted, const ['category']).isEmpty
                ? _inferOfflineCategory(input, isIncome)
                : _readFirstString(extracted, const ['category']),
            'date': DateFormat('yyyy-MM-dd').format(date),
          },
        );
      }

      return const _AssistantPlan(
        action: 'clarify',
        reply:
            "I can add that for you. Tell me the title and amount in one message.",
        data: {},
      );
    }

    if (_looksLikeDeleteIntent(lower)) {
      final target = <String, dynamic>{};
      final amount = _extractFirstAmount(input);
      final title = _guessOfflineTitle(input);
      final date = _extractDateFromInput(input);

      if (title.isNotEmpty) target['title'] = title;
      if (amount != null) target['amount'] = amount;
      if (date != null) {
        target['date'] = DateFormat('yyyy-MM-dd').format(date);
      }

      if (target.isNotEmpty) {
        return _AssistantPlan(
          action: 'delete_transaction',
          reply: '',
          data: {'target': target},
        );
      }

      return const _AssistantPlan(
        action: 'clarify',
        reply: "Tell me which transaction you want me to delete.",
        data: {},
      );
    }

    if (_looksLikeEditIntent(lower)) {
      return const _AssistantPlan(
        action: 'clarify',
        reply:
            "Tell me which transaction to edit and what should change, like the new amount or date.",
        data: {},
      );
    }

    // For chat queries, generate a contextual response
    final chatReply = _generateOfflineChatReply(input);
    return _AssistantPlan.chat(chatReply);
  }

  String _generateOfflineChatReply(String input) {
    final lower = input.toLowerCase();

    // Emotional support - sad, upset, stressed, etc.
    if ([
      'sad',
      'upset',
      'angry',
      'frustrated',
      'stressed',
      'worry',
      'worried',
      'depressed',
      'lonely',
      'unhappy',
    ].any(lower.contains)) {
      // Check if it's finance-related sadness
      if ([
        'expens',
        'money',
        'bill',
        'budget',
        'debt',
        'spent',
        'lost',
        'expensive',
      ].any(lower.contains)) {
        return "I hear you—money stress can be tough. 😔 But you're taking the right step by tracking it. Let me help you find areas to cut back or ways to earn more. Want to review your spending together?";
      }
      return "I'm sorry to hear that. 💙 Sometimes we all have tough moments. While I'm here to help with your finances, remember that money shouldn't define your happiness. Want to talk about your budget, or just vent?";
    }

    // Greetings
    if (['hi', 'hello', 'hey', 'greetings', 'howdy'].any(lower.contains)) {
      return "Hey! 👋 I'm Crixy, your wallet buddy. What would you like to know about your finances today? You can ask me about spending, budget, or tell me a transaction to track.";
    }

    // How are you
    if ([
      'how are you',
      'how\'s your day',
      'how\'s it going',
    ].any(lower.contains)) {
      return "I'm doing great, thanks for asking! 😊 Ready to help you manage your money wisely. What's on your mind?";
    }

    // Financial advice queries (personal analysis)
    if ([
      'advice',
      'analyze',
      'analysis',
      'suggest',
      'recommend',
      'tip',
    ].any(lower.contains)) {
      if ([
        'financial',
        'money',
        'spend',
        'budget',
        'save',
        'spending',
      ].any(lower.contains)) {
        return "🤔 Let me analyze your transactions and give you personalized advice based on your spending patterns...";
      }
    }

    // Category spending queries
    if ([
      'field',
      'category',
      'where',
      'which',
      'most',
      'spent',
      'spending',
    ].any((word) => lower.contains(word))) {
      if ([
        'most',
        'highest',
        'max',
        'spend',
      ].any((word) => lower.contains(word))) {
        return "📊 Let me calculate which category you spent the most in...";
      }
    }

    // Transaction history/details queries
    if ([
      'transaction',
      'history',
      'detail',
      'list',
      'show',
      'give me',
      'tell me',
      'what',
    ].any(lower.contains)) {
      // Check for time filters
      if ([
        'last two day',
        'past 2 day',
        '2 day',
        'two day',
      ].any(lower.contains)) {
        return "📊 Fetching your last 2 days' transactions...";
      }
      if ([
        'last.*week',
        'past week',
        'this week',
        '7 day',
        'week',
      ].any(lower.contains)) {
        return "📊 Getting your past week's transaction details...";
      }
      if ([
        'this month',
        'past month',
        'monthly',
        'month',
      ].any(lower.contains)) {
        return "📊 Pulling up this month's transactions...";
      }
      if (['today'].any(lower.contains)) {
        return "📊 Showing today's transactions...";
      }
      if (['yesterday'].any(lower.contains)) {
        return "📊 Showing yesterday's transactions...";
      }
      if (['total', 'sum', 'how much'].any(lower.contains)) {
        return "📊 Calculating your spending totals...";
      }
      return "📊 I'll pull up your transaction details. Want today's transactions, this week, this month, or a specific time period?";
    }

    // Expense reduction / advice with analysis
    if ([
      'reduce',
      'cut',
      'lower',
      'minimize',
      'save',
      'decrease',
    ].any(lower.contains)) {
      if (['expens', 'spend', 'cost'].any(lower.contains)) {
        if ([
          'next week',
          'coming week',
          'upcoming',
          'how',
        ].any(lower.contains)) {
          return "💡 Let me analyze your spending and suggest specific cuts. Give me a moment...";
        }
        return "Great question! Let me check which category ate up most of your budget and show you how to cut back.";
      }
    }

    // Savings / budget
    if (['save', 'budget', 'limit', 'how much'].any(lower.contains)) {
      if (['should', 'can', 'will'].any(lower.contains)) {
        return "To give you better advice, I'd need to see your income and spending patterns. Tell me—how much do you earn monthly, and where's your biggest expense?";
      }
    }

    // Non-finance general questions - deflect politely
    if ([
      'president',
      'weather',
      'sports',
      'movie',
      'film',
      'actor',
      'actress',
      'song',
      'music',
      'recipe',
      'cook',
      'history',
      'geography',
      'science',
      'math',
      'school',
      'university',
      'study',
    ].any(lower.contains)) {
      return "Ooh, that's an interesting question! 🤔 However, I'm specialized in helping you with your finances and wallet management. I'd be happy to help with budgeting, spending analysis, or transaction tracking instead. What would you like to know about your money? 💰";
    }

    // Default friendly response
    return "I'm here to help! 💰 You can ask me about your spending, add or manage transactions, or chat about money topics. What would you like to do?";
  }

  bool _looksLikeAddIntent(String input) {
    final lower = input.toLowerCase();

    // Check for explicit add actions
    final addKeywords = [
      'add ',
      'spent ',
      'spend ',
      'pay ',
      'paid ',
      'bought ',
      'purchased ',
      'earned ',
      'received ',
      'got ',
      'made ',
      'took ',
    ];
    final hasAddKeyword = addKeywords.any(lower.contains);

    if (!hasAddKeyword) return false;

    // Exclude queries about expenses/income that are NOT transaction additions
    final excludePatterns = [
      'how.*expens', // how to reduce expenses
      'reduce.*expens', // reduce expenses
      'lower.*expens', // lower expenses
      'save.*expens', // save on expenses
      'cut.*expens', // cut expenses
      'expens.*histor', // expense history
      'expens.*detail', // expense details
      'this.*month.*expens', // this month's expenses
      'this.*week.*expens', // this week's expenses
      'my.*expens', // my expenses
      'how.*income', // how to increase income
      'income.*histor', // income history
      'transaction.*detail', // transaction details
      'transaction.*list', // transaction list
      'show.*transaction', // show transactions
    ];

    if (excludePatterns.any(
      (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(lower),
    )) {
      return false;
    }

    return true;
  }

  bool _looksLikeDeleteIntent(String input) {
    final lower = input.toLowerCase();
    return [
      'delete ',
      'remove ',
      'erase ',
      'cancel ',
      'undo ',
    ].any(lower.contains);
  }

  bool _looksLikeEditIntent(String input) {
    final lower = input.toLowerCase();
    return [
      'edit ',
      'update ',
      'change ',
      'correct ',
      'modify ',
      'alter ',
    ].any(lower.contains);
  }

  bool _looksLikeIncomeIntent(String input) {
    return [
      'income',
      'earned',
      'received',
      'salary',
      'credit',
      'refund',
      'gift',
    ].any(input.contains);
  }

  double? _extractFirstAmount(String input) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)',
    ).firstMatch(input.replaceAll(',', ''));
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  DateTime? _extractDateFromInput(String input) {
    final lower = input.toLowerCase();
    final now = DateTime.now();

    if (lower.contains('today')) {
      return now; // Keep the full current time for today
    }
    if (lower.contains('yesterday')) {
      final day = now.subtract(const Duration(days: 1));
      return DateTime(day.year, day.month, day.day, now.hour, now.minute); // Preserve current hour/min for yesterday context
    }
    if (lower.contains('tomorrow')) {
      final day = now.add(const Duration(days: 1));
      return DateTime(day.year, day.month, day.day, now.hour, now.minute);
    }

    final parsed = _transactionService.tryParseDate(input);
    if (parsed != null) {
      // If parsed date is today, merge with current time to avoid "12 AM"
      if (parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
        return now;
      }
      return parsed;
    }
    return null;
  }

  String _guessOfflineTitle(String input) {
    // First try explicit extraction patterns (handles "from X", "named X", etc.)
    final explicitTitle = _extractExplicitTitle(input);
    if (explicitTitle.isNotEmpty) return explicitTitle;

    // Try to find a name/noun that looks like a person name
    final nameMatch = _extractProbableName(input);
    if (nameMatch.isNotEmpty) return nameMatch;

    // If explicit extraction didn't work, clean up the rest of the input
    var cleaned = input
        .replaceAll(RegExp(r'rs\.?', caseSensitive: false), '')
        .replaceAll(RegExp(r'rupees?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\d+(?:\.\d+)?'), '')
        .replaceAll(
          RegExp(
            r'\b(add|spent|spend|pay|paid|bought|earned|received|income|expense|delete|remove|edit|update|change|dated|date|today|yesterday|tomorrow|category|the|an|a|in|at|on|for|to|from|as)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.length > 50) {
      cleaned = cleaned.substring(0, 50).trim();
    }

    return cleaned;
  }

  String _extractProbableName(String input) {
    // List of common names (English, Indian, and other cultures)
    final commonNames = {
      'mom',
      'dad',
      'mother',
      'father',
      'brother',
      'sister',
      'son',
      'daughter',
      'grandma',
      'grandpa',
      'grandmother',
      'grandfather',
      'uncle',
      'aunt',
      'cousin',
      'wife',
      'husband',
      'friend',
      'boss',
      'colleague',
      'amma',
      'achan',
      'appa',
      'mummy',
      'papa',
      'bhai',
      'behen',
      'nani',
      'nana',
      'dadi',
      'dada',
      'mama',
      'mami',
      'kaka',
      'kaki',
      'shop',
      'store',
      'cafe',
      'restaurant',
      'coffee',
      'john',
      'jane',
      'david',
      'sarah',
      'michael',
      'emma',
      'robert',
      'anna',
      'raj',
      'priya',
      'amit',
      'neha',
      'vikram',
      'pooja',
      'arjun',
      'divya',
    };

    final lower = input.toLowerCase();

    // Look for common names in the input
    for (final name in commonNames) {
      if (lower.contains(RegExp(r'\b' + name + r'\b', caseSensitive: false))) {
        return name;
      }
    }

    // Try to extract capitalized words that might be names (non-English names)
    final namePattern = RegExp(r'\b([A-Z][a-z]+)\b');
    final matches = namePattern.allMatches(input);
    for (final match in matches) {
      final word = match.group(1)!.toLowerCase();
      // Avoid common words
      if (![
        'Add',
        'Spent',
        'For',
        'From',
        'The',
        'In',
        'On',
        'At',
        'Rs',
        'And',
        'Or',
      ].any((w) => w.toLowerCase() == word)) {
        return match.group(1)!;
      }
    }

    // Try to extract words between specific markers
    final betweenMarkers = RegExp(
      r'(?:name|from|in the name of|named|under)\s+([a-z]+)',
      caseSensitive: false,
    );
    final betweenMatch = betweenMarkers.firstMatch(input);
    if (betweenMatch != null) {
      final candidate = betweenMatch.group(1)!.trim();
      if (!_isTransactionKeyword(candidate) && !_isCategoryName(candidate)) {
        return candidate;
      }
    }

    return '';
  }

  String _inferOfflineCategory(String input, bool isIncome) {
    final lower = input.toLowerCase();

    if (isIncome) {
      if (lower.contains('salary')) return 'Salary';
      if (lower.contains('refund')) return 'Refund';
      if (lower.contains('gift')) return 'Gift';
      if (lower.contains('business') || lower.contains('freelance')) {
        return 'Business';
      }
      return 'Others';
    }

    if ([
      'food',
      'coffee',
      'restaurant',
      'zomato',
      'swiggy',
      'grocery',
      'groceries',
      'burger',
      'pizza',
      'lunch',
      'dinner',
    ].any(lower.contains)) {
      return 'Food';
    }
    if ([
      'uber',
      'ola',
      'taxi',
      'bus',
      'train',
      'metro',
      'fuel',
      'petrol',
      'travel',
      'ticket',
      'flight',
    ].any(lower.contains)) {
      return 'Travel';
    }
    if ([
      'amazon',
      'flipkart',
      'shopping',
      'mall',
      'myntra',
      'clothes',
    ].any(lower.contains)) {
      return 'Shopping';
    }
    if ([
      'rent',
      'bill',
      'electricity',
      'wifi',
      'internet',
      'subscription',
    ].any(lower.contains)) {
      return 'Bills';
    }
    return 'Others';
  }

  Future<Box?> _openUserTransactionBox() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final boxName = 'transactions_${user.email ?? user.uid}';
    return Hive.isBoxOpen(boxName) ? Hive.box(boxName) : Hive.openBox(boxName);
  }

  Future<void> _maybeSendProactiveInsight() async {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastInsightDate = await _crixyService.getLastInsightDate();
    if (lastInsightDate == todayKey) return;

    final insight = await _buildProactiveInsight();
    if (insight.isEmpty) return;

    await _sendBotMessage(insight);
    await _crixyService.setLastInsightDate(todayKey);
  }

  Future<String> _buildProactiveInsight() async {
    final transactions = await _transactionService.loadTransactions();
    if (transactions.isEmpty) {
      return "Quick note: once you log a few transactions, I can start spotting spending patterns and give smarter suggestions.";
    }

    final settingsBox = await _openUserTransactionBox();
    final spendingLimit =
        (settingsBox?.get('spending_limit', defaultValue: 0.0) as num?)
            ?.toDouble() ??
        0.0;
    final isLimitTodayOnly =
        settingsBox?.get('limit_today_only', defaultValue: true) == true;
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = DateFormat('yyyy-MM').format(now);

    var todayExpense = 0.0;
    var monthExpense = 0.0;
    var monthIncome = 0.0;
    final expenseByCategory = <String, double>{};

    for (final tx in transactions) {
      final amount = tx['amount'] as double? ?? 0.0;
      final dateKey = tx['date']?.toString() ?? '';
      final isIncome = tx['isIncome'] == true;

      if (dateKey == todayKey) {
        if (!isIncome) todayExpense += amount;
      }
      if (dateKey.startsWith(monthKey)) {
        if (isIncome) {
          monthIncome += amount;
        } else {
          monthExpense += amount;
          final category = tx['category']?.toString() ?? 'Others';
          expenseByCategory[category] =
              (expenseByCategory[category] ?? 0) + amount;
        }
      }
    }

    // Check budget status first
    if (spendingLimit > 0) {
      final trackedSpend = isLimitTodayOnly ? todayExpense : monthExpense;
      final limitPeriod = isLimitTodayOnly ? 'today' : 'this month';
      if (trackedSpend > spendingLimit) {
        final overBy = trackedSpend - spendingLimit;
        return "⚠️ You're over your $limitPeriod limit by Rs ${TransactionService.formatAmount(overBy)}. Let's discuss ways to control spending going forward.";
      }

      final ratio = trackedSpend / spendingLimit;
      if (ratio >= 0.90) {
        final left = spendingLimit - trackedSpend;
        return "🔔 Almost at your budget limit! You have Rs ${TransactionService.formatAmount(left)} left $limitPeriod. Be selective with next expenses.";
      }
      if (ratio >= 0.70) {
        final left = spendingLimit - trackedSpend;
        return "📊 You've used 70% of your $limitPeriod budget. Rs ${TransactionService.formatAmount(left)} remains. Steady pace so far.";
      }
    }

    // Analyze spending patterns
    final sortedCategories = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Check income to expense ratio
    if (monthIncome > 0 && monthExpense > 0) {
      final expenseRatio = (monthExpense / monthIncome) * 100;
      if (expenseRatio > 95) {
        return "⚠️ You're spending ${expenseRatio.toStringAsFixed(0)}% of your income this month. Almost nothing left to save. Cut expenses or boost income?";
      }
      if (expenseRatio > 80) {
        return "💡 You're spending ${expenseRatio.toStringAsFixed(0)}% of income—a bit high. Try cutting 10% to save more for emergencies.";
      }
      if (expenseRatio < 35) {
        return "🌟 Great savings rate! You're only spending ${expenseRatio.toStringAsFixed(0)}% of income. Keep it up!";
      }
    }

    // Spot biggest expense category
    if (sortedCategories.isNotEmpty) {
      final topCategory = sortedCategories[0].key;
      final topAmount = sortedCategories[0].value;
      final percentOfTotal = (topAmount / monthExpense) * 100;

      if (percentOfTotal > 40) {
        return "📍 $topCategory is your largest expense (${percentOfTotal.toStringAsFixed(0)}% of spending). Consider ways to reduce this category.";
      } else if (percentOfTotal > 30) {
        return "📌 Your biggest expense this month: $topCategory at Rs ${TransactionService.formatAmount(topAmount)}. I can help you track it.";
      }
    }

    // Default insight
    if (monthExpense > 0) {
      return "✨ Total spending this month: Rs ${TransactionService.formatAmount(monthExpense)}. Let me know if you'd like to optimize any category.";
    }

    return '';
  }

  Map<String, dynamic> _mergeAddTransactionData(
    Map<String, dynamic> aiData,
    String originalInput,
  ) {
    final merged = Map<String, dynamic>.from(aiData);
    final extracted = _extractStructuredTransaction(originalInput);

    final explicitTitle = _readFirstString(extracted, const ['title', 'name']);
    final aiTitle = _readFirstString(aiData, const ['title', 'name']);
    final fallbackTitle = _guessOfflineTitle(originalInput);

    if (explicitTitle.isNotEmpty) {
      merged['title'] = explicitTitle;
    } else if (_looksLikeNoisyTitle(aiTitle, originalInput)) {
      if (fallbackTitle.isNotEmpty) {
        merged['title'] = fallbackTitle;
      }
    } else if (aiTitle.isEmpty && fallbackTitle.isNotEmpty) {
      merged['title'] = fallbackTitle;
    }

    merged['amount'] =
        _readAmount(aiData['amount']) ??
        _readAmount(extracted['amount']) ??
        _extractFirstAmount(originalInput);

    final detectedType =
        _readTransactionType(aiData['type'] ?? aiData['isIncome']) ??
        _readTransactionType(extracted['type'] ?? extracted['isIncome']);
    if (detectedType != null) {
      merged['type'] = detectedType ? 'income' : 'expense';
    }

    final resolvedIsIncome =
        _readTransactionType(merged['type'] ?? merged['isIncome']) ??
        _looksLikeIncomeIntent(originalInput.toLowerCase());

    final extractedCategory = _readFirstString(extracted, const ['category']);
    final aiCategory = _readFirstString(aiData, const ['category']);
    final fallbackCategory = _inferOfflineCategory(
      originalInput,
      resolvedIsIncome,
    );
    merged['category'] = extractedCategory.isNotEmpty
        ? extractedCategory
        : aiCategory.isNotEmpty
        ? aiCategory
        : fallbackCategory;

    final date =
        _readDate(aiData['date']) ??
        _readDate(extracted['date']) ??
        _extractDateFromInput(originalInput);
    if (date != null) {
      merged['date'] = DateFormat('yyyy-MM-dd').format(date);
    }

    return merged;
  }

  Map<String, dynamic> _extractStructuredTransaction(String input) {
    final lower = input.toLowerCase();
    final isIncome = _looksLikeIncomeIntent(lower);
    final amount = _extractFirstAmount(input);
    final title = _extractExplicitTitle(input);
    final date = _extractDateFromInput(input);

    final data = <String, dynamic>{};
    if (amount != null) data['amount'] = amount;
    data['type'] = isIncome ? 'income' : 'expense';

    final category = _inferOfflineCategory(input, isIncome);
    if (category.isNotEmpty) {
      data['category'] = category;
    }
    if (title.isNotEmpty) {
      data['title'] = title;
    }
    if (date != null) {
      data['date'] = DateFormat('yyyy-MM-dd').format(date);
    }
    return data;
  }

  String _extractExplicitTitle(String input) {
    final patterns = <RegExp>[
      // "in the name of X", "named X", "in the name X"
      RegExp(
        r"\b(?:in the name of|in the name|name of|named|under name|name is)\s+([a-z][a-z0-9 ._'-]{0,35})(?:\s+(?:as|for|expense|income|category|towards|toward|food|travel|shopping|bills|on|at|eating|buying|bought)|$)",
        caseSensitive: false,
      ),
      // "from X" - extract person/name
      RegExp(
        r"\bfrom\s+([a-z][a-z0-9 ._'-]{0,25}?)(?:\s+(?:as|for|towards|toward|category|food|travel|shopping|bills|expense|income|on|at|eating|buying|bought)|$)",
        caseSensitive: false,
      ),
      // "title X" or "title: X"
      RegExp(
        r"\btitle\s*:?\s*(?:as\s+)?([a-z][a-z0-9 ._'-]{0,35})(?:\s+(?:as|for|expense|income|towards|toward|on|at|eating)|$)",
        caseSensitive: false,
      ),
      // "for X" where X is a person/place (at end or before category)
      RegExp(
        r"\bfor\s+([a-z][a-z0-9 ._'-]{0,25}?)(?:\s+(?:food|travel|shopping|bills|category|towards|toward|expense|income|on|at|eating)|$)",
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match == null) continue;
      final candidate = _cleanupExtractedTitle(match.group(1) ?? '');
      if (candidate.isNotEmpty &&
          !_isCategoryName(candidate) &&
          !_isTransactionKeyword(candidate)) {
        return candidate;
      }
    }

    return '';
  }

  bool _isTransactionKeyword(String value) {
    final keywords = [
      'expense',
      'income',
      'add',
      'spent',
      'earned',
      'paid',
      'received',
      'cost',
      'bill',
    ];
    return keywords.contains(value.toLowerCase());
  }

  bool _isCategoryName(String value) {
    final categories = [
      'food',
      'travel',
      'shopping',
      'bills',
      'salary',
      'business',
      'gift',
      'refund',
      'others',
    ];
    return categories.contains(value.toLowerCase());
  }

  String _cleanupExtractedTitle(String value) {
    // Remove all transaction and category keywords
    var cleaned = value
        .replaceAll(
          RegExp(
            r'\b(?:today|yesterday|tomorrow|towards|toward|category|as|for|on|at|in|the|an|a|food|travel|shopping|bills|salary|business|gift|refund|expense|income|spent|earned|paid|received|add|cost|bill|eating|buying|bought|with|rs|rupees)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\d+(?:\.\d+)?'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // If empty after cleanup, return original value
    if (cleaned.isEmpty) {
      return value;
    }

    // If it looks like a person name (short, no numbers), keep it
    if (cleaned.length <= 20 && !RegExp(r'\d').hasMatch(cleaned)) {
      return cleaned;
    }

    // Otherwise return as is
    return cleaned;
  }

  bool _looksLikeNoisyTitle(String title, String originalInput) {
    final cleanedTitle = title.trim().toLowerCase();
    final cleanedInput = originalInput.trim().toLowerCase();
    if (cleanedTitle.isEmpty) return true;
    if (cleanedTitle == cleanedInput) return true;
    if (cleanedTitle.length > 40) return true;
    if (RegExp(r'\d').hasMatch(cleanedTitle)) return true;
    if ([
      'expense',
      'income',
      'towards',
      'toward',
      'category',
      'add',
      'spent',
      'paid',
    ].any(cleanedTitle.contains)) {
      return true;
    }
    return false;
  }

  String _readFirstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  double? _readAmount(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble().abs();

    final text = value.toString().replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(0)!)?.abs();
  }

  bool? _readTransactionType(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    if (['income', 'credit', 'earned', 'receive', 'received'].contains(text)) {
      return true;
    }
    if (['expense', 'debit', 'spent', 'pay', 'paid'].contains(text)) {
      return false;
    }
    return null;
  }

  DateTime? _readDate(dynamic value) {
    if (value == null) return null;
    return _transactionService.tryParseDate(value.toString());
  }

  String _formatTransactionDate(String? rawDate) {
    final parsed = _transactionService.tryParseDate(rawDate);
    if (parsed == null) return rawDate ?? 'that day';
    return _transactionService.formatDateForChat(parsed);
  }

  String _safeReply(String raw, {required String fallback}) {
    return _sanitizePlainReply(raw, fallback: fallback);
  }

  String _sanitizePlainReply(String raw, {required String fallback}) {
    final cleaned = raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty || _looksLikeJson(cleaned)) {
      return fallback;
    }

    return cleaned;
  }

  bool _looksLikeJson(String value) {
    final trimmed = value.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        trimmed.contains('"action"') ||
        trimmed.contains('"data"');
  }

  DateTime _startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String _nextMessageId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<void> _saveAndDisplayMsg(ChatMessage msg) async {
    if (!mounted) return;
    setState(() {
      _messages.add(msg);
    });
    _scrollToBottom();

    try {
      await _hiveService.saveMessage(msg);
      await _dbService.saveMessage(msg);
    } catch (e) {
      debugPrint('CRIXY_SYNC_ERROR: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Clear Chat',
          style: TextStyle(
            fontFamily: 'Pixel',
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'Are you sure you want to clear chat?',
          style: TextStyle(color: Colors.white70, fontFamily: 'Qarume'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey, fontFamily: 'Qarume'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red, fontFamily: 'Qarume'),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _hiveService.clearChat();
      await _dbService.clearChat();
      await _crixyService.setSeenIntro(false);

      if (!mounted) return;
      Navigator.pop(context);
      setState(() {
        _messages.clear();
        _showChatUI = false;
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFF0F0F0F));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: null, // Removed top bar as requested
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _FogBackground(),
          Column(
            children: [
              _buildCustomHeader(),
              Expanded(
                child: _showChatUI ? _buildChatInterface() : _buildIntroInterface(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text(
            'Crixy',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Pixel',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: _clearChat,
          ),
        ],
      ),
    );
  }

  Widget _buildIntroInterface() {
    return Center(
      key: const ValueKey('IntroUI'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/animations/Crixy_Hello.json',
            height: 250,
            repeat: false,
          ),
        ],
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      key: const ValueKey('ChatUI'),
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return _ChatBubble(msg: msg);
            },
          ),
        ),
        if (_isResponding)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Crixy is thinking...',
                style: TextStyle(
                  color: Colors.white54,
                  fontFamily: 'Qarume',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.add, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      enabled: !_isResponding,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Qarume', fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Add a message...',
                        hintStyle: TextStyle(color: Colors.white38, fontFamily: 'Qarume', fontSize: 15),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 2),
                      ),
                      onSubmitted: _handleUserSubmit,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isResponding ? null : () => _handleUserSubmit(_msgController.text),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _isResponding ? const Color(0xFF3F3F46) : const Color(0xFF6366F1),
                shape: BoxShape.circle,
                boxShadow: [
                  if (!_isResponding)
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({super.key, required this.msg});

  final ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF18181B),
              ),
              clipBehavior: Clip.hardEdge,
              child: Lottie.asset(
                'assets/animations/Crixy.json',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF8B5CF6) // More vibrant purple for user
                    : const Color(0xFF27272A), // Dark zinc for Crixy
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: Text(
                msg.message,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Qarume', // User requested Crix (Qarume) for the text
                  fontSize: 15,
                  height: 1.4,
                ),
                softWrap: true,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantPlan {
  const _AssistantPlan({
    required this.action,
    required this.reply,
    required this.data,
  });

  const _AssistantPlan.chat(String reply)
    : action = 'chat',
      reply = reply,
      data = const {};

  final String action;
  final String reply;
  final Map<String, dynamic> data;

  factory _AssistantPlan.fromJson(Map<String, dynamic> json) {
    final action = json['action']?.toString().trim().toLowerCase() ?? 'chat';
    final reply = json['reply']?.toString().trim() ?? '';
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};

    return _AssistantPlan(
      action: action.isEmpty ? 'chat' : action,
      reply: reply,
      data: data,
    );
  }
}

class _FogBackground extends StatefulWidget {
  const _FogBackground();

  @override
  State<_FogBackground> createState() => _FogBackgroundState();
}

class _FogBackgroundState extends State<_FogBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_FogCloud> _clouds = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    // Initialize 6 diverse fog clouds
    for (int i = 0; i < 6; i++) {
      _clouds.add(_FogCloud(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 150 + _random.nextDouble() * 200,
        opacity: 0.02 + _random.nextDouble() * 0.06, // Significantly reduced opacity
        velocity: Offset(
          (_random.nextDouble() - 0.5) * 0.0005,
          (_random.nextDouble() - 0.5) * 0.0005,
        ),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _FogPainter(_clouds, _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _FogCloud {
  double x, y, radius, opacity;
  Offset velocity;

  _FogCloud({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.velocity,
  });
}

class _FogPainter extends CustomPainter {
  final List<_FogCloud> clouds;
  final double animationValue;

  _FogPainter(this.clouds, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    for (var cloud in clouds) {
      // Calculate current position with orbital drift
      final driftX = math.sin(animationValue * math.pi * 2 + cloud.x * 10) * 0.05;
      final driftY = math.cos(animationValue * math.pi * 2 + cloud.y * 10) * 0.05;

      final posX = ((cloud.x + driftX + (animationValue * cloud.velocity.dx * 100)) % 1.0) * size.width;
      final posY = ((cloud.y + driftY + (animationValue * cloud.velocity.dy * 100)) % 1.0) * size.height;

      final paint = Paint()
        ..color = const Color(0xFFE2E8F0).withValues(alpha: cloud.opacity) // Muted blue-grey tone
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);

      canvas.drawCircle(Offset(posX, posY), cloud.radius, paint);

      // Draw mirrored versions for seamless wrap
      if (posX + cloud.radius > size.width) {
        canvas.drawCircle(Offset(posX - size.width, posY), cloud.radius, paint);
      }
      if (posX - cloud.radius < 0) {
        canvas.drawCircle(Offset(posX + size.width, posY), cloud.radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) => true;
}
