import 'dart:math';
import 'package:flutter/material.dart';

class HomeWidget extends StatelessWidget {
  const HomeWidget(
      {super.key,
      required this.image,
      this.color,
      this.height,
      this.width,
      this.padding,
      this.decoration,
      this.onTap});
  final ImageProvider<Object> image;
  final Color? color;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    // final Color randomColor = getrandomColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: decoration ??
            BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: color,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 5,
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
        width: width ?? screenWidth * 0.96,
        height: height ?? screenHeight * 0.25,
        child: Center(
          child: Image(
            image: image,
            height: 140,
            width: 140,
          ),
        ),
      ),
    );
  }

  Color getrandomColor() {
    final Random random = Random();

    return Color.fromARGB(
        255,
        random.nextInt(256),
        random.nextInt(256), // green
        random.nextInt(256));
  }
}
