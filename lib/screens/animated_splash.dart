import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';

class AnimatedSplash extends StatefulWidget {
  const AnimatedSplash({super.key});

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> {
  final player = AudioPlayer();

  // control each letter visibility
  List<bool> showLetter = [false, false, false, false];
  bool isReady = false;

  @override
  void initState() {
    super.initState();
    // Delay to prevent flickering
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => isReady = true);
        startSequence();
      }
    });
  }

  void startSequence() async {
    // play full bubble audio
    try {
      await player.play(AssetSource('voice/transition.wav'));
    } catch (e) {
      print('Audio error: $e');
    }

    // 💥 Letter timings (your exact timings)

    // C - 0.64s
    Future.delayed(const Duration(milliseconds: 630), () {
      setState(() => showLetter[0] = true);
    });

    // R - 1.76s
    Future.delayed(const Duration(milliseconds: 1750), () {
      setState(() => showLetter[1] = true);
    });

    // I - 2.77s
    Future.delayed(const Duration(milliseconds: 2750), () {
      setState(() => showLetter[2] = true);
    });

    // X - 3.56s
    Future.delayed(const Duration(milliseconds: 3550), () {
      setState(() => showLetter[3] = true);
    });

    // navigate after animation
    await Future.delayed(const Duration(seconds: 5));

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Widget buildLetter(String letter, int index) {
    return AnimatedScale(
      scale: showLetter[index] ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut, // 💥 pop effect
      child: AnimatedOpacity(
        opacity: showLetter[index] ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              fontFamily: 'Qarume',
              letterSpacing: 2,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [
                    Color.fromARGB(255, 255, 255, 255),
                    Color.fromARGB(255, 255, 255, 255),
                    Color.fromARGB(255, 255, 255, 255),
                  ],
                ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isReady) {
      return Container(color: const Color(0xFF0F0F0F));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // 💰 Center coin animation
          Center(
            child: Lottie.asset(
              'assets/animations/coins_drop.json',
              width: 220,
              repeat: false,
            ),
          ),

          // 🔥 Bottom CRIX text
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildLetter('C', 0),
                  buildLetter('R', 1),
                  buildLetter('I', 2),
                  buildLetter('X', 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
