import 'package:flutter/material.dart';

void main() => runApp(const FindMyThingsApp());

class FindMyThingsApp extends StatelessWidget {
  const FindMyThingsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FindMyThings',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F6F1),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF173F35)),
    ),
    home: const HomeScreen(),
  );
}

class Belonging {
  const Belonging(this.name, this.category, this.icon, this.tint);
  final String name;
  final String category;
  final IconData icon;
  final Color tint;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const forest = Color(0xFF173F35);
  final List<Belonging> _items = [
    const Belonging('Everyday wallet', 'Accessories', Icons.account_balance_wallet_outlined, Color(0xFFE9DCC8)),
    const Belonging('House keys', 'Essentials', Icons.key_outlined, Color(0xFFE5E8D8)),
    const Belonging('Headphones', 'Electronics', Icons.headphones_outlined, Color(0xFFE4E0EF)),
    const Belonging('Wristwatch', 'Accessories', Icons.watch_outlined, Color(0xFFE8E2D8)),
  ];
  int _selectedTab = 0;

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFFEFA),
        title: const Text('Add a belonging', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g. My camera',
            filled: true,
            fillColor: const Color(0xFFF2F1EB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Add item')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => _items.insert(0, Belonging(name, 'My belongings', Icons.inventory_2_outlined, const Color(0xFFE5E8D8))));
    }
    controller.dispose();
  }

  void _showFindMessage(Belonging item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFEFA),
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ready when you are', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: forest)),
          const SizedBox(height: 8),
          Text('Next, we’ll use your camera to look for \${item.name}. Camera matching is the next development step.',
            style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF656B65))),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          sliver: SliverList(delegate: SliverChildListDelegate([
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 23)),
              const SizedBox(width: 11),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FindMyThings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: forest)),
                Text('A little peace of mind.', style: TextStyle(fontSize: 11, color: Color(0xFF858A82))),
              ]),
              const Spacer(),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.tune_rounded, color: forest, size: 20)),
            ]),
            const SizedBox(height: 34),
            const Text('YOUR EVERYDAY COMPANION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.8, color: Color(0xFF858A82))),
            const SizedBox(height: 9),
            const Text('Keep track of\nwhat matters.', style: TextStyle(fontSize: 34, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: Color(0xFF202A24))),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: forest.withValues(alpha: 0.13), blurRadius: 22, offset: const Offset(0, 10))]),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR LITTLE INVENTORY', style: TextStyle(color: Color(0xFFB8C9BD), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 9),
                  Text('\${_items.length} things saved', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  const SizedBox(height: 5),
                  const Text('All in one place, right on your phone.', style: TextStyle(color: Color(0xFFD0DDD4), fontSize: 11)),
                ])),
                Container(width: 58, height: 58, decoration: BoxDecoration(color: const Color(0xFF315D50), borderRadius: BorderRadius.circular(19)),
                  child: const Icon(Icons.inventory_2_outlined, color: Color(0xFFE6EBDD), size: 28)),
              ]),
            ),
            const SizedBox(height: 29),
            Row(children: [
              const Expanded(child: Text('Your belongings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF202A24), letterSpacing: -0.5))),
              TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add, size: 18), label: const Text('Add new'),
                style: TextButton.styleFrom(foregroundColor: forest, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 5),
            const Text('Choose an item when you need help finding it.', style: TextStyle(color: Color(0xFF858A82), fontSize: 12)),
            const SizedBox(height: 15),
          ])),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 110),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = _items[index];
              return Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: const Color(0xFFFFFEFA), borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: const Color(0xFFECEBE4))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 46, height: 46, decoration: BoxDecoration(color: item.tint, borderRadius: BorderRadius.circular(15)),
                    child: Icon(item.icon, color: forest, size: 23)),
                  const Spacer(),
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF26312A))),
                  const SizedBox(height: 3),
                  Text(item.category, style: const TextStyle(fontSize: 10, color: Color(0xFF858A82))),
                  const SizedBox(height: 11),
                  SizedBox(width: double.infinity, height: 34,
                    child: OutlinedButton(onPressed: () => _showFindMessage(item),
                      style: OutlinedButton.styleFrom(foregroundColor: forest, side: const BorderSide(color: Color(0xFFD8E0D8)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)), padding: EdgeInsets.zero),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.search_rounded, size: 15), SizedBox(width: 5),
                        Text('Find item', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ]))),
                ]),
              );
            }, childCount: _items.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 13, crossAxisSpacing: 13, childAspectRatio: 0.91),
          ),
        ),
      ]),
    ),
    floatingActionButton: FloatingActionButton(onPressed: _addItem, backgroundColor: forest, foregroundColor: Colors.white,
      elevation: 3, child: const Icon(Icons.add_rounded, size: 27)),
    bottomNavigationBar: NavigationBar(
      height: 70, backgroundColor: const Color(0xFFFFFEFA), indicatorColor: const Color(0xFFE5EDE5),
      selectedIndex: _selectedTab, onDestinationSelected: (index) => setState(() => _selectedTab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'My things'),
        NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Recent'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    ),
  );
}
