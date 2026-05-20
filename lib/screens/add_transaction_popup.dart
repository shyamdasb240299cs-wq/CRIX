import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddTransactionPopupScreen extends StatefulWidget {
  const AddTransactionPopupScreen({super.key});

  @override
  State<AddTransactionPopupScreen> createState() => _AddTransactionPopupScreenState();
}

class _AddTransactionPopupScreenState extends State<AddTransactionPopupScreen> {
  String name = "";
  String amount = "";
  bool isIncome = false;
  static const MethodChannel _channel = MethodChannel('com.example.wallet_app/overlay');

  @override
  void initState() {
    super.initState();
    // Use SystemChannels to set the transparent background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }

  void _submitTransaction() async {
    if (name.isNotEmpty && amount.isNotEmpty) {
      FocusScope.of(context).unfocus();
      try {
        await _channel.invokeMethod('submitTransaction', {
          'name': name,
          'amount': double.parse(amount),
          'isIncome': isIncome,
        });
      } catch (e) {
        // Handle error gracefully
      }
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () {
          SystemNavigator.pop(); // Close on backdrop tap
        },
        child: Container(
          color: Colors.black45, // Soft dim background
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xD909090B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border(top: BorderSide(color: Color(0xFF27272A))),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 24,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          onChanged: (val) => amount = val,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => isIncome = false);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: !isIncome
                                        ? const Color(0xFFF43F5E).withValues(alpha: 0.15)
                                        : const Color(0xFF18181B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: !isIncome ? const Color(0xFFF43F5E) : Colors.transparent,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Expense",
                                      style: TextStyle(
                                        fontFamily: 'Qarume',
                                        color: !isIncome ? const Color(0xFFF43F5E) : Colors.white54,
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
                                  setState(() => isIncome = true);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: isIncome
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : const Color(0xFF18181B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isIncome ? const Color(0xFF10B981) : Colors.transparent,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Income",
                                      style: TextStyle(
                                        fontFamily: 'Qarume',
                                        color: isIncome ? const Color(0xFF10B981) : Colors.white54,
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
                          onPressed: _submitTransaction,
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
