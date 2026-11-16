import 'dart:async';

import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('staff subscribe to assigned schools and only the open school detail',
      () async {
    final schools = _Schools();
    final staff = Staff(
      id: 'staff',
      name: 'Driver',
      assignedSchoolIds: ['one', 'two'],
      createdAt: DateTime(2025),
    );
    final container = ProviderContainer(
      overrides: [
        schoolsRepositoryProvider.overrideWithValue(schools),
        isAdminProvider.overrideWithValue(false),
        currentStaffProvider.overrideWith((_) => Stream.value(staff)),
      ],
    );
    addTearDown(container.dispose);
    final subscriptions = [
      container.listen(schoolsProvider, (_, __) {}),
      container.listen(schoolByIdProvider('one'), (_, __) {}),
      container.listen(schoolByIdProvider('unassigned'), (_, __) {}),
    ];
    await container.read(schoolsProvider.future);
    expect(await container.read(schoolByIdProvider('one').future), isNull);
    expect(
        await container.read(schoolByIdProvider('unassigned').future), isNull);
    expect(
        schools.queries,
        unorderedEquals([
          ['one', 'two'],
          ['one']
        ]));

    for (final subscription in subscriptions) {
      subscription.close();
    }
    await container.pump();
    expect(container.exists(schoolByIdProvider('one')), isFalse);
    expect(container.exists(schoolsProvider), isFalse);
  });

  test('reads rooms concurrently and propagates a pack failure', () async {
    final schools = _Schools();
    addTearDown(schools.dispose);
    final container = ProviderContainer(
      overrides: [schoolsRepositoryProvider.overrideWithValue(schools)],
    );
    addTearDown(container.dispose);
    final provider = schoolTotalProvider('school');
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);

    final totals = expectLater(
      container.read(provider.future),
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(schools.packWatches, unorderedEquals(['a', 'b']));

    schools.packs['b']!.addError(StateError('load failed'));
    await totals;
  });

  test('incompatible units never produce a school consumables total', () async {
    final schools = _Schools();
    addTearDown(schools.dispose);
    final container = ProviderContainer(
      overrides: [schoolsRepositoryProvider.overrideWithValue(schools)],
    );
    addTearDown(container.dispose);
    final provider = schoolConsumablesTotalsProvider('school');
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    await expectLater(
      container.read(provider.future),
      throwsA(isA<StateError>()),
    );
  });
}

class _Schools implements SchoolsRepository {
  final queries = <List<String>?>[];
  final packWatches = <String>[];
  final packs = {
    'a': StreamController<PackTotal?>.broadcast(),
    'b': StreamController<PackTotal?>.broadcast(),
  };

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) {
    queries.add(schoolIds);
    return Stream.value(const []);
  }

  @override
  Stream<List<YearLevel>> watchYearLevels(String schoolId) => Stream.value(
      [YearLevel(id: 'level', label: 'Year 1', createdAt: DateTime(2025))]);

  @override
  Stream<List<Classroom>> watchClassrooms(
          String schoolId, String yearLevelId) =>
      Stream.value([
        Classroom(id: 'a', name: 'A', createdAt: DateTime(2025)),
        Classroom(id: 'b', name: 'B', createdAt: DateTime(2025)),
      ]);

  @override
  Stream<PackTotal?> watchLatestPackTotal(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) {
    packWatches.add(classroomId);
    return packs[classroomId]!.stream;
  }

  @override
  Stream<List<Consumable>> watchClassroomConsumables(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) =>
      Stream.value([
        Consumable(
          id: classroomId,
          itemName: 'Paper',
          quantity: 2,
          unit: classroomId == 'a' ? 'reams' : 'boxes',
          createdAt: DateTime(2025),
        ),
      ]);

  Future<void> dispose() async {
    for (final stream in packs.values) {
      await stream.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
