import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/offline_media.dart';
import 'package:bts_delivery_app/providers/offline_media_providers.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/widgets/offline_media_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('viewer opens the verified local file without asking for a URL',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('offline-media-view');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preview.png')
      ..writeAsBytesSync(
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+sp1QAAAAASUVORK5CYII='),
      );
    const visit = DeliveryVisit(deliveryId: 'visit-a', schoolId: 'school-a');
    final asset = OfflineMediaAsset.schoolMap(
      bucket: 'approved.firebasestorage.app',
      schoolId: visit.schoolId,
      visit: visit,
      reference: 'schools/school-a/map/preview.png',
    )!;
    final owner = StateProvider<String?>((_) => 'person-a');
    final changes = StreamController<OfflineMediaState>();
    addTearDown(changes.close);
    var urlReads = 0;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        offlineMediaOwnerProvider.overrideWith((ref, _) => ref.watch(owner)),
        offlineMediaAssetStateProvider.overrideWith((ref, _) => changes.stream),
        onlineMediaUrlProvider.overrideWith((ref, _) async {
          urlReads++;
          throw StateError('A local preview must not fetch a URL');
        }),
        isOnlineProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OfflineMediaPreview(asset: asset, expectedUid: 'person-a'),
        ),
      ),
    ));
    changes.add((
      phase: OfflineMediaPhase.ready,
      localPath: file.path,
      verifiedAt: DateTime.utc(2026),
      issue: null,
      progress: null,
    ));
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
    expect(urlReads, 0);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OfflineMediaPreview)),
    );
    container.read(owner.notifier).state = 'person-b';
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Media unavailable to this account'), findsOneWidget);
    expect(urlReads, 0);
  });
}
