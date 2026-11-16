import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/schools_providers.dart';
import '../../services/date_utils.dart';
import '../../models/delivery.dart';
import '../../models/school.dart';

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

  void _loadDeliveryData(
      Delivery delivery, List<School> schools) {
    // Only load if we haven't loaded this specific delivery yet
    if (_loadedDeliveryId == delivery.id) return;

    debugPrint('Loading delivery ${delivery.id} for school: ${delivery.schoolName}');

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
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
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

  Widget _buildForm(BuildContext context, AsyncValue<List<School>> schoolsAsync) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Delivery' : 'Add Delivery'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // School selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'School',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      schoolsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) =>
                            Text('Error loading schools: $error'),
                        data: (schools) => DropdownButtonFormField<School>(
                          initialValue: _selectedSchool,
                          decoration: InputDecoration(
                            hintText: 'Select a school',
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF00aeef), width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          validator: (value) {
                            if (value == null) {
                              return 'Please select a school';
                            }
                            return null;
                          },
                          borderRadius: BorderRadius.circular(12),
                          dropdownColor: Colors.white,
                          elevation: 8,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                            height: 1.5,
                          ),
                          icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 28),
                          isExpanded: true,
                          isDense: false,
                          items: schools
                              .map((school) => DropdownMenuItem(
                                    value: school,
                                    child: Text(
                                      school.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (school) {
                            setState(() {
                              _selectedSchool = school;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Date and time selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schedule',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),

                      // Date
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Date'),
                        subtitle: Text(DateTimeUtils.formatDate(_selectedDate)),
                        onTap: _selectDate,
                        contentPadding: EdgeInsets.zero,
                      ),

                      // Time (optional)
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Time (Optional)'),
                        subtitle: Text(_selectedTime != null
                            ? _selectedTime!.format(context)
                            : 'No time selected'),
                        trailing: _selectedTime != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _selectedTime = null;
                                  });
                                },
                              )
                            : null,
                        onTap: _selectTime,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Vehicle Count
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vehicles Required',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedVehicleCount,
                        decoration: InputDecoration(
                          hintText: 'Select number of vehicles (optional)',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF00aeef), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: Colors.white,
                        elevation: 8,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          height: 1.5,
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 28),
                        isExpanded: true,
                        items: List.generate(10, (index) => index + 1)
                            .map((count) => DropdownMenuItem<int>(
                                  value: count,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.local_shipping, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        count == 1 ? '$count vehicle' : '$count vehicles',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedVehicleCount = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Pallet Count
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pallets',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedPalletCount,
                        decoration: InputDecoration(
                          hintText: 'Select number of pallets (optional)',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF00aeef), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: Colors.white,
                        elevation: 8,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                          height: 1.5,
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 28),
                        isExpanded: true,
                        items: List.generate(20, (index) => index + 1)
                            .map((count) => DropdownMenuItem<int>(
                                  value: count,
                                  child: Row(
                                    children: [
                                      const Icon(Symbols.pallet, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        count == 1 ? '$count pallet' : '$count pallets',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPalletCount = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          hintText: 'Optional delivery notes...',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              FilledButton(
                onPressed: _isLoading ? null : _saveDelivery,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Delivery'),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          backgroundColor: Colors.red,
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

      debugPrint('Saving delivery for ${_selectedSchool!.name} on ${DateTimeUtils.formatDate(_selectedDate)}');

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
              backgroundColor: Colors.green,
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
              backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
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
