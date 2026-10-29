import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum ItemType { lost, found }

enum ItemCategory {
  electronics('Electronics', Icons.devices),
  bags('Bags', Icons.backpack),
  idCards('IDs & Cards', Icons.badge),
  keys('Keys', Icons.key),
  clothing('Clothing', Icons.checkroom),
  books('Books & Notes', Icons.menu_book),
  other('Other', Icons.category);

  const ItemCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Known spots on campus, so reports are consistent and easy to search.
const List<String> campusLocations = [
  'Library',
  'Canteen',
  'Covered Court',
  'CCIS building',
  'CAS building',
  'Function Hall',
  'CFIN building',
  'Parking Lot',
  'Other',
];

class CampusItem {
  CampusItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.category,
    required this.location,
    required this.contact,
    required this.postedAt,
    this.photo,
    this.isReturned = false,
  });

  final String id;
  final String title;
  final String description;
  final ItemType type;
  final ItemCategory category;
  final String location;
  final String contact;
  final DateTime postedAt;

  /// Raw image bytes. Using bytes instead of file paths lets the photo
  /// display on every platform, including web.
  final Uint8List? photo;

  bool isReturned;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'type': type.name,
        'category': category.name,
        'location': location,
        'contact': contact,
        'postedAt': postedAt.toIso8601String(),
        'isReturned': isReturned,
        if (photo != null) 'photoBase64': base64Encode(photo!),
      };

  factory CampusItem.fromJson(Map<String, dynamic> json) {
    return CampusItem(
      id: json['id'] as String? ?? 'item-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: ItemType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ItemType.lost,
      ),
      category: ItemCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => ItemCategory.other,
      ),
      location: json['location'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      postedAt: DateTime.tryParse(json['postedAt'] as String? ?? '') ??
          DateTime.now(),
      isReturned: json['isReturned'] == true,
      photo: json['photoBase64'] != null
          ? base64Decode(json['photoBase64'] as String)
          : null,
    );
  }
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
