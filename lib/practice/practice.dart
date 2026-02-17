import 'dart:math';

import 'package:flutter/material.dart';

class Practice extends StatefulWidget {
  const Practice({super.key});

  @override
  State<Practice> createState() => _PracticeState();
}

class _PracticeState extends State<Practice> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }

  String villainName() {
    List title = ['The', 'Lord', 'Doctor', 'Queen', 'Captain', 'Baron'];
    List trait = ['Venom', 'Doom', 'Chaos', 'Hex', 'Whisper', 'Blight'];
    List emoji = ['🦹‍♀️', '🐍', '😈', '🧿', '👿', '🔥'];
    Random random = Random();

    String pickedtitle = title[random.nextInt(title.length)];
    String pickedtrait = trait[random.nextInt(trait.length)];
    String pickedemoji = emoji[random.nextInt(emoji.length)];

    return ('Your villain name is: $pickedtitle $pickedtrait $pickedemoji');
  }
}
