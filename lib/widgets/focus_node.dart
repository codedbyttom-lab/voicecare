import 'package:flutter/material.dart';

class NoKeyboardFocusNode extends FocusNode {
  @override
  bool consumeKeyboardToken() => false;
}
