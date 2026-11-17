import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/schools_providers.dart';
import '../../services/date_utils.dart';
import '../../models/delivery.dart';
import '../../models/school.dart';
import '../../widgets/design/design.dart';

class AddEditDeliveryScreen extends ConsumerStatefulWidget {
  const AddEditDeliveryScreen({super.key, this.deliveryId});

  final String? deliveryId;
  bool get isEditing => deliveryId != null;

  @override
  ConsumerState<AddEditDeliveryScreen> createState() =>
      _AddEditDeliveryScreenState();
}

class _AddEditDeliveryScreenState extends ConsumerState<AddEditDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  School? _selectedSchool;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  int? _selectedVehicleCount;
  int? _selectedPalletCount;
  bool _isLoading = false;
  String? _loadedDeliveryId;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _loadDeliveryData(Delivery delivery, List<School> schools) {
    // Only load if we haven't loaded this specific delivery yet
    if (_loadedDeliveryId == delivery.id) return;

    debugPrint(
        'Loading delivery ${delivery.id} for school: ${delivery.schoolName}');

    setState(() {
      _loadedDeliveryId = delivery.id;
      _selectedSchool = schools.firstWhere(
        (school) => school.id == delivery.schoolId,
        orElse: () => School(
          id: delivery.schoolId,
          name: delivery.schoolName,
          address: '',
          createdAt: DateTime.now(),
        ),
      );
      _selectedDate = delivery.date;
      if (delivery.time != null) {
        _selectedTime = TimeOfDay.fromDateTime(delivery.time!);
      }
      _selectedVehicleCount = delivery.vehicleCount;
      _selectedPalletCount = delivery.palletCount;
      if (delivery.notes != null) {
        _notesController.text = delivery.notes!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsProvider);

    // Load existing delivery data when editing
    if (widget.isEditing && widget.deliveryId != null) {
      final deliveryAsync = ref.watch(deliveryByIdProvider(widget.deliveryId!));

      // Show loading or error states
      return deliveryAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(
            title: const Text('Edit Delivery'),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Edit Delivery'),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Error loading delivery: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
        data: (delivery) {
          if (delivery == null) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Edit Delivery'),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 64),
                    const SizedBox(height: 16),
                    const Text('Delivery not found'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            );
          }

          // Load the delivery data
          schoolsAsync.whenData((schools) {
            _loadDeliveryData(delivery, schools);
          });

          // Continue to show the form below
          return _buildForm(context, schoolsAsync);
        },
      );
    }

    return _buildForm(context, schoolsAsync);
  }

  Widget _buildForm(
      BuildContext context, AsyncValue<List<School>> schoolsAsync) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Delivery' : 'Add Delivery'),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter,
              10,
              AppTokens.gutter,
              AppTokens.sectionGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _formSection(
                  'School',
                  schoolsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Text('Error loading schools: $error'),
                    data: (schools) => DropdownButtonFormField<School>(
                      initialValue: _selectedSchool,
                      decoration:
                          const InputDecoration(hintText: 'Select a school'),
                      borderRadius:
                          BorderRadius.circular(AppTokens.controlRadius),
                      dropdownColor: AppPalette.of(context).surface,
                      icon: const Icon(Icons.expand_more),
                      itemHeight: null,
                      isExpanded: true,
                      items: [
                        for (final school in schools)
                          DropdownMenuItem(
                            value: school,
                            child: _menuLabel(school.name),
                          ),
                      ],
                      validator: (value) =>
                          value == null ? 'Please select a school' : null,
                      onChanged: (school) =>
                          setState(() => _selectedSchool = school),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const AppSectionHeading(title: 'Schedule'),
                const SizedBox(height: 8),
                AppGroupedList(
                  children: [
                    ListTile(
                      leading: const AppIconTile(
                          icon: Icons.calendar_today_outlined),
                      title: const Text('Date'),
                      subtitle: Text(DateTimeUtils.formatDate(_selectedDate)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _selectDate,
                    ),
                    ListTile(
                      leading: const AppIconTile(icon: Icons.schedule_outlined),
                      title: const Text('Time (Optional)'),
                      subtitle: Text(
                          _selectedTime?.format(context) ?? 'No time selected'),
                      trailing: _selectedTime == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Clear selected time',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _selectedTime = null),
                            ),
                      onTap: _selectTime,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _formSection(
                  'Vehicles Required',
                  _countField(
                    value: _selectedVehicleCount,
                    count: 10,
                    label: 'vehicle',
                    onChanged: (value) =>
                        setState(() => _selectedVehicleCount = value),
                  ),
                ),
                const SizedBox(height: 12),
                _formSection(
                  'Pallets',
                  _countField(
                    value: _selectedPalletCount,
                    count: 20,
                    label: 'pallet',
                    onChanged: (value) =>
                        setState(() => _selectedPalletCount = value),
                  ),
                ),
                const SizedBox(height: 12),
                _formSection(
                  'Notes',
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                        hintText: 'Optional delivery notes...'),
                    maxLines: 3,
                  ),
                ),
                const SizedBox(height: AppTokens.sectionGap),
                FilledButton(
                  onPressed: _isLoading ? null : _saveDelivery,
                  child: _isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Delivery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _formSection(String title, Widget child) => AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeading(title: title),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _menuLabel(String value) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(value),
          ),
        ),
      );

  Widget _countField({
    required int? value,
    required int count,
    required String label,
    required ValueChanged<int?> onChanged,
  }) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        decoration: const InputDecoration(hintText: 'Optional'),
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        dropdownColor: AppPalette.of(context).surface,
        icon: const Icon(Icons.expand_more),
        itemHeight: null,
        isExpanded: true,
        items: [
          for (var number = 1; number <= count; number++)
            DropdownMenuItem(
              value: number,
              child: _menuLabel(
                  number == 1 ? '$number $label' : '$number ${label}s'),
            ),
        ],
        onChanged: onChanged,
      );

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  Future<void> _saveDelivery() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSchool == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a school'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      DateTime? deliveryDateTime;
      if (_selectedTime != null) {
        deliveryDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      }

      final delivery = Delivery(
        id: widget.deliveryId ?? '',
        schoolId: _selectedSchool!.id,
        schoolName: _selectedSchool!.name,
        date: DateTimeUtils.startOfDay(_selectedDate),
        time: deliveryDateTime,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        vehicleCount: _selectedVehicleCount,
        palletCount: _selectedPalletCount,
        createdAt: DateTime.now(),
      );

      debugPrint(
          'Saving delivery for ${_selectedSchool!.name} on ${DateTimeUtils.formatDate(_selectedDate)}');

      final deliveriesNotifier = ref.read(deliveriesNotifierProvider.notifier);
      final success = widget.isEditing
          ? await deliveriesNotifier.updateDelivery(delivery)
          : await deliveriesNotifier.createDelivery(delivery);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isEditing
                  ? 'Delivery updated successfully'
                  : 'Delivery created successfully'),
            ),
          );
          // Navigate back to deliveries page
          context.go('/home');
        } else {
          final errorState = ref.read(deliveriesNotifierProvider);
          final errorMessage =
              errorState.error?.toString() ?? 'Failed to save delivery';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
