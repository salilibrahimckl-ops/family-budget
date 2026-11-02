import 'package:flutter/material.dart';

/// A budget category. "goal" categories (chitti, savings) show progress
/// towards a target instead of money left to spend.
class Cat {
  final String id;
  final String label;
  final String iconKey;
  final Color color;
  final bool goal;
  final bool custom; // created in Developer options
  final bool hidden;
  final List<String> keywords; // extra auto-detect words (lower case)

  const Cat(this.id, this.label, this.iconKey, this.color,
      {this.goal = false, this.custom = false, this.hidden = false, this.keywords = const []});

  IconData get icon => kIconChoices[iconKey] ?? Icons.label;

  Cat copyWith({String? label, String? iconKey, Color? color, bool? goal, bool? hidden, List<String>? keywords}) =>
      Cat(id, label ?? this.label, iconKey ?? this.iconKey, color ?? this.color,
          goal: goal ?? this.goal,
          custom: custom,
          hidden: hidden ?? this.hidden,
          keywords: keywords ?? this.keywords);
}

/// Icons a category can use. Must be const so release builds keep them.
const kIconChoices = <String, IconData>{
  'restaurant': Icons.restaurant,
  'grocery': Icons.local_grocery_store,
  'car': Icons.directions_car,
  'bag': Icons.shopping_bag,
  'fun': Icons.celebration,
  'groups': Icons.groups,
  'savings': Icons.savings,
  'more': Icons.more_horiz,
  'medical': Icons.medical_services,
  'school': Icons.school,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'phone': Icons.smartphone,
  'child': Icons.child_care,
  'gift': Icons.card_giftcard,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
  'flight': Icons.flight,
  'fuel': Icons.local_gas_station,
  'mosque': Icons.mosque,
  'heart': Icons.volunteer_activism,
  'book': Icons.menu_book,
  'tv': Icons.tv,
  'build': Icons.build,
  'cafe': Icons.local_cafe,
  'spa': Icons.spa,
  'bank': Icons.account_balance,
  'label': Icons.label,
};

const kColorChoices = <Color>[
  Color(0xFFE0663E), Color(0xFF3E9B5B), Color(0xFF2F7FC1), Color(0xFF9B59B6),
  Color(0xFFD9A21B), Color(0xFF16808A), Color(0xFF1F6F43), Color(0xFF7A7A7A),
  Color(0xFFC0392B), Color(0xFF8E5A2B), Color(0xFF3949AB), Color(0xFFD81B60),
];

const kBuiltInCats = <Cat>[
  Cat('food', 'Food', 'restaurant', Color(0xFFE0663E)),
  Cat('grocery', 'Grocery', 'grocery', Color(0xFF3E9B5B)),
  Cat('travel', 'Travel', 'car', Color(0xFF2F7FC1)),
  Cat('shopping', 'Shopping', 'bag', Color(0xFF9B59B6)),
  Cat('fun', 'Fun', 'fun', Color(0xFFD9A21B)),
  Cat('chitti', 'Chitti', 'groups', Color(0xFF16808A), goal: true),
  Cat('savings', 'Savings', 'savings', Color(0xFF1F6F43), goal: true),
  Cat('other', 'Other', 'more', Color(0xFF7A7A7A)),
];

const kUncategorised = 'uncategorised';
const kIgnored = 'ignored';
const _untagged = Cat(kUncategorised, 'To tag', 'label', Color(0xFFB0453A));

/// Holds the family's categories: built-ins (possibly renamed / hidden) plus
/// custom ones from Developer options. Stored on the family document under
/// `cats: { id: {label, icon, color, goal, hidden, custom, keywords} }`.
class CatStore {
  static List<Cat> all = List.of(kBuiltInCats);

  static void apply(Map<String, dynamic>? familyData) {
    final raw = familyData?['cats'];
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final out = <Cat>[];
    for (final b in kBuiltInCats) {
      final o = m[b.id];
      out.add(o is Map ? _merge(b, Map<String, dynamic>.from(o)) : b);
    }
    final customs = m.entries.where((e) => e.value is Map && (e.value as Map)['custom'] == true).toList()
      ..sort((a, b) => ((a.value as Map)['order'] as num? ?? 0).compareTo((b.value as Map)['order'] as num? ?? 0));
    for (final e in customs) {
      final d = Map<String, dynamic>.from(e.value as Map);
      out.add(Cat(
        e.key,
        d['label'] as String? ?? e.key,
        d['icon'] as String? ?? 'label',
        Color((d['color'] as num?)?.toInt() ?? 0xFF7A7A7A),
        goal: d['goal'] == true,
        custom: true,
        hidden: d['hidden'] == true,
        keywords: _kw(d['keywords']),
      ));
    }
    all = out;
  }

  static Cat _merge(Cat b, Map<String, dynamic> o) => b.copyWith(
        label: o['label'] as String?,
        iconKey: o['icon'] as String?,
        color: o['color'] is num ? Color((o['color'] as num).toInt()) : null,
        hidden: o['hidden'] as bool?,
        keywords: _kw(o['keywords']),
      );

  static List<String> _kw(dynamic v) => v is List
      ? v.map((e) => '$e'.trim().toLowerCase()).where((e) => e.isNotEmpty).toList()
      : const [];

  /// Category whose Developer-options keywords appear in the payee, if any.
  static String? matchKeywords(String payee, String? vpa) {
    final hay = '${payee.toLowerCase()} ${vpa?.toLowerCase() ?? ''}';
    for (final c in all) {
      if (c.hidden) continue;
      for (final k in c.keywords) {
        if (hay.contains(k)) return c.id;
      }
    }
    return null;
  }
}

/// Visible categories, in display order.
List<Cat> get kCats => CatStore.all.where((c) => !c.hidden).toList();

Cat catById(String id) => CatStore.all.firstWhere((c) => c.id == id, orElse: () => _untagged);
