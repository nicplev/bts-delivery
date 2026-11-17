import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/schools_providers.dart';
import '../../services/date_utils.dart';
import '../../models/delivery.dart';
import '../../models/school.dart';
import '../../widgets/delivery_day_list.dart';
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

  String get _title => widget.isEditing ? 'Edit delivery' : 'Add delivery';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _loadDeliveryData(Delivery delivery, List<School> schools) {
    // Only load if we haven't loaded this specific delivery yet
    if (_loadedDeliveryId == delivery.id) return;

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
        loading: () => _stateScaffold(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (error, _) => _stateScaffold(
          DeliveryMessage(
            icon: AppIcons.error,
            title: 'Error loading delivery: $error',
            action: AppSecondaryButton(
              label: 'Go back',
              expand: false,
              onPressed: () => context.pop(),
            ),
          ),
        ),
        data: (delivery) {
          if (delivery == null) {
            return _stateScaffold(
              DeliveryMessage(
                icon: AppIcons.search,
                title: 'Delivery not found',
                action: AppSecondaryButton(
                  label: 'Go back',
                  expand: false,
                  onPressed: () => context.pop(),
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

  /// Loading / error / not-found states under the same chrome as the form.
  Widget _stateScaffold(Widget content) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const AppNavBar(),
        body: Builder(
          builder: (context) => ListView(
            padding: AppInsets.scroll(context),
            children: [
              AppLargeTitle(title: _title),
              const SizedBox(height: AppTokens.sectionGap - 8),
              content,
            ],
          ),
        ),
      );

  Widget _buildForm(
      BuildContext context, AsyncValue<List<School>> schoolsAsync) {
    final colors = AppPalette.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppNavBar(),
      body: AppFloatingActionArea(
        action: AppGlassPrimaryButton(
          label: 'Save delivery',
          loading: _isLoading,
          onPressed: _saveDelivery,
        ),
        child: Builder(
          builder: (context) => Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: AppInsets.scroll(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLargeTitle(
                    title: _title,
                    subtitle: _selectedSchool?.name,
                  ),
                  _section(
                    'School',
                    AppPanel(
                      child: schoolsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Text(
                          'Error loading schools: $error',
                          style: AppTypography.subheadline
                              .copyWith(color: colors.error),
                        ),
                        data: (schools) => DropdownButtonFormField<School>(
                          initialValue: _selectedSchool,
                          decoration: const InputDecoration(
                              hintText: 'Select a school'),
                          borderRadius:
                              BorderRadius.circular(AppTokens.controlRadius),
                          dropdownColor: colors.surface,
                          icon:
                              Icon(AppIcons.chevronDown, color: colors.chevron),
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
                  ),
                  _section(
                    'Schedule',
                    AppGroupedList(
                      separatorIndent: 57,
                      children: [
                        AppListRow(
                          icon: AppIcons.calendar,
                          title: 'Date',
                          subtitle: DateTimeUtils.formatDate(_selectedDate),
                          onTap: _selectDate,
                        ),
                        AppListRow(
                          icon: AppIcons.timer,
                          title: 'Time (optional)',
                          subtitle: _selectedTime?.format(context) ??
                              'No time selected',
                          showChevron: _selectedTime == null,
                          trailing: _selectedTime == null
                              ? null
                              : IconButton(
                                  tooltip: 'Clear selected time',
                                  icon: Icon(AppIcons.close,
                                      size: 20, color: colors.muted),
                                  onPressed: () =>
                                      setState(() => _selectedTime = null),
                                ),
                          onTap: _selectTime,
                        ),
                      ],
                    ),
                  ),
                  _section(
                    'Load',
                    AppPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _fieldLabel('Vehicles required'),
                          _countField(
                            value: _selectedVehicleCount,
                            count: 10,
                            label: 'vehicle',
                            onChanged: (value) =>
                                setState(() => _selectedVehicleCount = value),
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel('Pallets'),
                          _countField(
                            value: _selectedPalletCount,
                            count: 20,
                            label: 'pallet',
                            onChanged: (value) =>
                                setState(() => _selectedPalletCount = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _section(
                    'Notes',
                    AppPanel(
                      child: TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                            hintText: 'Optional delivery notes...'),
                        maxLines: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A grouped form section: muted label above its card.
  Widget _section(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: AppTokens.sectionGap - 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionLabel(label),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          text,
          style: AppTypography.subheadline.copyWith(
            color: AppPalette.of(context).ink,
            fontWeight: FontWeight.w600,
          ),
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
        icon: Icon(AppIcons.chevronDown, color: AppPalette.of(context).chevron),
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
