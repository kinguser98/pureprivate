import 'package:flutter/material.dart';

class LanguageItem {
  const LanguageItem({
    required this.name,
    required this.filterValue,
    required this.backdropUrl,
    required this.gradient,
  });

  final String name;
  final String filterValue;
  final String backdropUrl;
  final LinearGradient gradient;
}
