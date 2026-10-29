import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'campus_item.dart';
import 'item_store.dart';

class PostItemScreen extends StatefulWidget {
  const PostItemScreen({super.key, required this.store});

  final ItemStore store;

  @override
  State<PostItemScreen> createState() => _PostItemScreenState();
}

class _PostItemScreenState extends State<PostItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactController = TextEditingController();
  final _picker = ImagePicker();

  ItemType _type = ItemType.lost;
  ItemCategory _category = ItemCategory.other;
  String? _location;
  Uint8List? _photo;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1080,
      imageQuality: 75,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _photo = bytes);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    widget.store.add(
      CampusItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        type: _type,
        category: _category,
        location: _location!,
        contact: _contactController.text.trim(),
        postedAt: DateTime.now(),
        photo: _photo,
      ),
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item posted. Thanks for helping out!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Report an item')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<ItemType>(
              segments: const [
                ButtonSegment(
                  value: ItemType.lost,
                  label: Text('I lost something'),
                  icon: Icon(Icons.search_off),
                ),
                ButtonSegment(
                  value: ItemType.found,
                  label: Text('I found something'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),

            // Photo preview
            Container(
              height: 180,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _photo == null
                  ? const Center(child: Text('No photo added yet'))
                  : Image.memory(_photo!, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                    onPressed: () => _pickPhoto(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'e.g. Blue water bottle',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please enter a name for the item'
                  : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<ItemCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in ItemCategory.values)
                  DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(c.icon, size: 18),
                        const SizedBox(width: 8),
                        Text(c.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _location,
              decoration: InputDecoration(
                labelText: _type == ItemType.lost
                    ? 'Where did you lose it?'
                    : 'Where did you find it?',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final loc in campusLocations)
                  DropdownMenuItem(value: loc, child: Text(loc)),
              ],
              validator: (value) =>
                  value == null ? 'Please choose a campus location' : null,
              onChanged: (value) => setState(() => _location = value),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Color, brand, stickers, what was inside...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'How can the owner reach you?',
                hintText: 'Email, phone, or Messenger',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Please add a way to contact you'
                  : null,
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Post item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
