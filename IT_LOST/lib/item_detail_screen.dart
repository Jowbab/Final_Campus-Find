import 'package:flutter/material.dart';

import 'campus_item.dart';
import 'item_store.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    super.key,
    required this.store,
    required this.itemId,
  });

  final ItemStore store;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final item = store.byId(itemId);

        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This item is no longer listed.')),
          );
        }

        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(item.type == ItemType.lost ? 'Lost item' : 'Found item'),
            actions: [
              IconButton(
                tooltip: 'Delete listing',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, item),
              ),
            ],
          ),
          body: ListView(
            children: [
              if (item.photo != null)
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(item.photo!, fit: BoxFit.cover),
                )
              else
                Container(
                  height: 160,
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(item.category.icon, size: 64),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(icon: Icons.category, text: item.category.label),
                    _InfoRow(icon: Icons.place, text: item.location),
                    _InfoRow(icon: Icons.schedule, text: timeAgo(item.postedAt)),
                    _InfoRow(icon: Icons.contact_mail, text: item.contact),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(item.description),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: Icon(
                        item.isReturned ? Icons.undo : Icons.check_circle,
                      ),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          item.isReturned
                              ? 'Mark as not returned'
                              : 'Mark as returned to owner',
                        ),
                      ),
                      onPressed: () => store.toggleReturned(item.id),
                    ),
                    if (item.isReturned)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'This item has been returned. It is hidden from '
                          'search unless you tap the eye icon on the home screen.',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, CampusItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      store.remove(item.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
