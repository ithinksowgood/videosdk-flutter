import 'dart:math';

int min = 0;
int max = 10000000;

// ignore: strict_top_level_inference
get randomNumber => min + (Random().nextInt(max - min));
