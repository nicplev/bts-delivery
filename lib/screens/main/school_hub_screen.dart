import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/schools_providers.dart';
import '../../widgets/records_tab.dart';
import '../../widgets/signoff_tab.dart';
import '../../widgets/info_tab.dart';
import '../../widgets/school_timer_widget.dart';

class SchoolHubScreen extends ConsumerStatefulWidget {
  const SchoolHubScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  ConsumerState<SchoolHubScreen> createState() => _SchoolHubScreenState();
}

class _SchoolHubScreenState extends ConsumerState<SchoolHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsProvider);

    return schoolsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('School')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
            ],
          ),
        ),
      ),
      data: (schools) {
        final school =
            schools.where((s) => s.id == widget.schoolId).firstOrNull;

        if (school == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('School Not Found')),
            body: const Center(
              child: Text('The selected school could not be found.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(school.name),
                if (school.address?.isNotEmpty == true)
                  Text(
                    school.address!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Records'),
                Tab(text: 'Sign-Off'),
                Tab(text: 'Info'),
              ],
            ),
          ),
          body: Column(
            children: [
              // Timer widget - visible on all tabs
              SchoolTimerWidget(schoolId: widget.schoolId),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    RecordsTab(schoolId: widget.schoolId),
                    SignOffTab(schoolId: widget.schoolId),
                    InfoTab(schoolId: widget.schoolId),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
