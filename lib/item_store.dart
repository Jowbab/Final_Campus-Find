import 'package:flutter/foundation.dart';

import 'campus_item.dart';
import 'local_json_storage.dart';

/// Holds all reported items and notifies listeners when they change.
/// Data is persisted locally using JSON (campusfind_items.json).
class ItemStore extends ChangeNotifier {
  ItemStore({
    List<CampusItem>? seed,
    LocalJsonStorage? storage,
    this.fileName = 'campusfind_items.json',
  })  : _storage = storage ?? LocalJsonStorage(),
        _items = [...?seed] {
    _loadFromStorage();
  }

  final LocalJsonStorage _storage;
  final String fileName;
  final List<CampusItem> _items;

  Future<void> _loadFromStorage() async {
    try {
      final savedList = await _storage.readJsonList(fileName);
      if (savedList != null && savedList.isNotEmpty) {
        _items.clear();
        for (final entry in savedList) {
          if (entry is Map<String, dynamic>) {
            _items.add(CampusItem.fromJson(entry));
          }
        }
        notifyListeners();
      } else if (_items.isEmpty) {
        _items.addAll(sampleItems());
        await _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ItemStore Local JSON] Could not load saved items: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final list = _items.map((item) => item.toJson()).toList();
      await _storage.writeJsonList(fileName, list);
    } catch (e) {
      debugPrint('[ItemStore Local JSON] Error saving items: $e');
    }
  }

  CampusItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Returns matching items, newest first.
  List<CampusItem> filter({
    String query = '',
    ItemCategory? category,
    ItemType? type,
    bool showReturned = false,
  }) {
    final q = query.trim().toLowerCase();

    final results = _items.where((item) {
      if (!showReturned && item.isReturned) return false;
      if (category != null && item.category != category) return false;
      if (type != null && item.type != type) return false;
      if (q.isEmpty) return true;

      return item.title.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q);
    }).toList();

    results.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return results;
  }

  void add(CampusItem item) {
    _items.add(item);
    notifyListeners();
    _saveToStorage();
  }

  void toggleReturned(String id) {
    final item = byId(id);
    if (item == null) return;
    item.isReturned = !item.isReturned;
    notifyListeners();
    _saveToStorage();
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
    _saveToStorage();
  }
}

/// Demo data so the app isn't empty on first launch.
List<CampusItem> sampleItems() {
  final now = DateTime.now();
  return [
    CampusItem(
      id: 'seed-1',
      title: 'Black wallet',
      description: 'Black leather wallet lost near the main entrance.',
      type: ItemType.lost,
      category: ItemCategory.other,
      location: 'Ayala Center',
      contact: 'owner@campus.edu',
      postedAt: now.subtract(const Duration(hours: 2)),
    ),
    CampusItem(
      id: 'seed-2',
      title: 'House keys',
      description: 'A small set of house keys found near the food court.',
      type: ItemType.found,
      category: ItemCategory.keys,
      location: 'SM Seaside',
      contact: 'Leave a message in the lost & found group chat',
      postedAt: now.subtract(const Duration(hours: 5)),
    ),
    CampusItem(
      id: 'seed-3',
      title: 'Blue backpack',
      description: 'Blue backpack left in a lecture room.',
      type: ItemType.lost,
      category: ItemCategory.bags,
      location: 'USC campus',
      contact: 'student@campus.edu',
      postedAt: now.subtract(const Duration(days: 1)),
    ),
    CampusItem(
      id: 'seed-4',
      title: 'Phone case',
      description: 'Clear phone case found near the parking area.',
      type: ItemType.found,
      category: ItemCategory.electronics,
      location: 'IT Park',
      contact: 'finder@campus.edu',
      postedAt: now.subtract(const Duration(days: 1)),
    ),
  ];
}
