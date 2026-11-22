import 'package:flutter/material.dart';

import 'campus_item.dart';
import 'auth_store.dart';
import 'item_detail_screen.dart';
import 'item_store.dart';
import 'post_item_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.authStore,
    this.accountName,
    this.onSignOut,
  });

  final ItemStore store;
  final AuthStore authStore;
  final String? accountName;
  final VoidCallback? onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  ItemCategory? _category;
  ItemType? _type;
  bool _showReturned = false;
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return Scaffold(
      body: SafeArea(
        child: _selectedTab == 0
            ? _homeContent(store)
            : _selectedTab == 2
                ? const _MessagesTab()
                : _selectedTab == 3
                    ? _ProfileTab(
                        authStore: widget.authStore,
                        accountName: widget.accountName,
                        onSignOut: widget.onSignOut,
                      )
                    : const SizedBox.shrink(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton(
              tooltip: 'Report an item',
              onPressed: () => _selectTab(1),
              child: const Icon(Icons.add, size: 32),
            )
          : null,
    );
  }

  Future<void> _selectTab(int index) async {
    if (index == 1) {
      setState(() => _selectedTab = 1);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PostItemScreen(store: widget.store),
        ),
      );
      if (mounted) setState(() => _selectedTab = 0);
      return;
    }
    setState(() => _selectedTab = index);
  }

  Widget _homeContent(ItemStore store) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Text(
            'Lost & Found',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search items, places...',
              prefixIcon: const Icon(Icons.search, size: 28),
              suffixIcon: IconButton(
                tooltip: 'Filter items',
                onPressed: _showFilters,
                icon: const Icon(Icons.tune),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Wrap(
            spacing: 10,
            children: [
              _TypeFilterChip(
                label: 'All',
                selected: _type == null,
                onSelected: () => setState(() => _type = null),
              ),
              _TypeFilterChip(
                label: 'Lost',
                selected: _type == ItemType.lost,
                onSelected: () => setState(() => _type = ItemType.lost),
              ),
              _TypeFilterChip(
                label: 'Found',
                selected: _type == ItemType.found,
                onSelected: () => setState(() => _type = ItemType.found),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final items = store.filter(
                query: _query,
                category: _category,
                type: _type,
                showReturned: _showReturned,
              );
              if (items.isEmpty) {
                return const Center(child: Text('No items match your search.'));
              }

              final width = MediaQuery.sizeOf(context).width;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: width >= 700 ? 3 : 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 18,
                  childAspectRatio: width >= 700 ? 0.86 : 0.72,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ItemCard(
                    item: item,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItemDetailScreen(
                          store: store,
                          itemId: item.id,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Category',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final category in ItemCategory.values)
                      FilterChip(
                        avatar: Icon(category.icon, size: 18),
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (selected) {
                          setState(
                              () => _category = selected ? category : null);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show returned items'),
                  value: _showReturned,
                  onChanged: (value) {
                    setState(() => _showReturned = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});

  final CampusItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.photo != null)
                    Image.memory(item.photo!, fit: BoxFit.cover)
                  else
                    ColoredBox(
                      color: _placeholderColor(item.category),
                      child: Center(
                        child: Icon(
                          item.category.icon,
                          size: 38,
                          color: Colors.black.withValues(alpha: 0.13),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _StatusBadge(
                      type: item.type,
                      returned: item.isReturned,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            decoration: item.isReturned
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${item.location} · ${timeAgo(item.postedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _placeholderColor(ItemCategory category) => switch (category) {
      ItemCategory.other => const Color(0xFFDCEBFC),
      ItemCategory.keys => const Color(0xFFDFF2F0),
      ItemCategory.bags => const Color(0xFFFBE1E1),
      ItemCategory.electronics => const Color(0xFFFFF6DE),
      ItemCategory.idCards => const Color(0xFFE9E5FA),
      ItemCategory.clothing => const Color(0xFFE7EEF2),
      ItemCategory.books => const Color(0xFFF6EBDD),
    };

class _TypeFilterChip extends StatelessWidget {
  const _TypeFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        backgroundColor: Colors.white,
        selectedColor: Theme.of(context).colorScheme.primary,
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFFE0E4E9),
        ),
      );
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 44,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('Messages', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'No messages yet.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.authStore,
    required this.accountName,
    required this.onSignOut,
  });

  final AuthStore authStore;
  final String? accountName;
  final VoidCallback? onSignOut;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _facebookController;
  late final TextEditingController _instagramController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.authStore.accountName ?? widget.accountName ?? '',
    );
    _emailController = TextEditingController(
      text: widget.authStore.accountEmail ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.authStore.accountPhone ?? '',
    );
    _facebookController = TextEditingController(
      text: widget.authStore.facebookLink ?? '',
    );
    _instagramController = TextEditingController(
      text: widget.authStore.instagramLink ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final error = await widget.authStore.updateProfile(
      name: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      facebookLink: _facebookController.text,
      instagramLink: _instagramController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error ?? 'Profile details saved.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Add contact details so people can reach you about an item.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            _ProfileField(
              controller: _nameController,
              label: 'Full name',
              icon: Icons.person_outline,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 16),
            _ProfileField(
              controller: _emailController,
              label: 'Email address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _validateProfileEmail,
            ),
            const SizedBox(height: 16),
            _ProfileField(
              controller: _phoneController,
              label: 'Phone number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _ProfileField(
              controller: _facebookController,
              label: 'Facebook profile link',
              icon: Icons.facebook,
              keyboardType: TextInputType.url,
              validator: _validateOptionalLink,
            ),
            const SizedBox(height: 16),
            _ProfileField(
              controller: _instagramController,
              label: 'Instagram profile link',
              icon: Icons.camera_alt_outlined,
              keyboardType: TextInputType.url,
              validator: _validateOptionalLink,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save profile'),
              ),
            ),
            if (widget.onSignOut != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ],
        ),
      );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
        validator: validator,
      );
}

String? _validateProfileEmail(String? value) {
  final email = value?.trim() ?? '';
  final atIndex = email.indexOf('@');
  if (atIndex <= 0 ||
      atIndex == email.length - 1 ||
      !email.contains('.', atIndex)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _validateOptionalLink(String? value) {
  final link = value?.trim() ?? '';
  if (link.isEmpty) return null;
  final uri = Uri.tryParse(link);
  if (uri == null ||
      !uri.hasAuthority ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return 'Enter a full link starting with https://';
  }
  return null;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.type, required this.returned});

  final ItemType type;
  final bool returned;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    if (returned) {
      label = 'Returned';
      color = Colors.green;
    } else if (type == ItemType.lost) {
      label = 'Lost';
      color = Colors.red;
    } else {
      label = 'Found';
      color = const Color(0xFFFFB800);
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: type == ItemType.found && !returned
              ? const Color(0xFF202124)
              : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
