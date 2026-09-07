import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../resources/resources.dart';
import '../dashboard/dashboard_screen.dart';
import '../hub/hub_screen.dart';
import '../more/more_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardScreen(),
      HubScreen(
        title: 'Production',
        subtitle: 'Record what happens on the farm every day.',
        specs: productionSpecs,
      ),
      HubScreen(
        title: 'Finance',
        subtitle: 'Track the money coming in and going out.',
        specs: financeSpecs,
      ),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Iconsax.home), selectedIcon: Icon(Iconsax.home_1), label: 'Home'),
          NavigationDestination(
              icon: Icon(Iconsax.chart_2), selectedIcon: Icon(Iconsax.chart_1), label: 'Production'),
          NavigationDestination(
              icon: Icon(Iconsax.wallet_2), selectedIcon: Icon(Iconsax.wallet_1), label: 'Finance'),
          NavigationDestination(
              icon: Icon(Iconsax.menu), selectedIcon: Icon(Iconsax.menu_1), label: 'More'),
        ],
      ),
    );
  }
}
