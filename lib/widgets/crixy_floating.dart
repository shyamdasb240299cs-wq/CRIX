import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../screens/crixy.dart';

// Global state to hide/show the floating widget without complex route observers
final ValueNotifier<bool> showCrixyFloatingNotifier = ValueNotifier<bool>(true);

class CrixyFloatingButton extends StatelessWidget {
  const CrixyFloatingButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showCrixyFloatingNotifier,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();

        return FloatingActionButton(
          onPressed: () {
            showCrixyFloatingNotifier.value = false;
            
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const CrixyScreen())
            ).then((_) {
              showCrixyFloatingNotifier.value = true;
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
              shape: BoxShape.circle,
            ),
            width: 70,
            height: 70,
            child: Lottie.asset('assets/animations/Crixy.json'),
          ),
        );
      },
    );
  }
}

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();
