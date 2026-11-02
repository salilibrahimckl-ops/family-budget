import 'package:flutter/material.dart';

/// Budget categories. "goal" categories (chitti, savings) show progress
/// towards a target instead of money left to spend.
class Cat {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool goal;
  const Cat(this.id, this.label, this.icon, this.color, {this.goal = false});
}

const kCats = <Cat>[
  Cat('food', 'Food', Icons.restaurant, Color(0xFFE0663E)),
  Cat('grocery', 'Grocery', Icons.local_grocery_store, Color(0xFF3E9B5B)),
  Cat('travel', 'Travel', Icons.directions_car, Color(0xFF2F7FC1)),
  Cat('shopping', 'Shopping', Icons.shopping_bag, Color(0xFF9B59B6)),
  Cat('fun', 'Fun', Icons.celebration, Color(0xFFD9A21B)),
  Cat('chitti', 'Chitti', Icons.groups, Color(0xFF16808A), goal: true),
  Cat('savings', 'Savings', Icons.savings, Color(0xFF1F6F43), goal: true),
  Cat('other', 'Other', Icons.more_horiz, Color(0xFF7A7A7A)),
];

const kUncategorised = 'uncategorised';
const kIgnored = 'ignored';

Cat catById(String id) => kCats.firstWhere(
      (c) => c.id == id,
      orElse: () => const Cat(kUncategorised, 'To tag', Icons.help_outline, Color(0xFFB0453A)),
    );
