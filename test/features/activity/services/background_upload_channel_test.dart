import 'dart:io';

import 'package:endurain/features/activity/models/activity_type.dart';
import 'package:endurain/features/activity/models/local_activity_record.dart';
import 'package:endurain/features/activity/repositories/local_activity_repository.dart';
import 'package:endurain/features/activity/services/activity_upload_queue.dart';
import 'package:endurain/features/activity/services/activity_upload_service.dart';
import 'package:endurain/features/activity/services/background_upload_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../helpers/sqlite_local_activity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late LocalActivityRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'endurain_background_upload_',
    );
    repository = createTestLocalActivityRepository(tempDirectory);
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  ActivityUploadQueue queueReturning(int status) => ActivityUploadQueue(
    repository: repository,
    uploadService: ActivityUploadService(
      config: const ActivityUploadConfig(
        endpoint: '/upload',
        fieldName: 'file',
      ),
      uploadFile:
          (
            _,
            _,
            _, {
            idempotencyKey,
            expectedOrigin,
            expectedProfileId,
          }) async =>
              http.StreamedResponse(const Stream<List<int>>.empty(), status),
    ),
    retryBackoff: const [Duration(minutes: 1)],
  );

  Future<void> createPendingRecord() async {
    const id = 'bg_pending';
    final fileName = await repository.writeGpx(id: id, gpx: '<gpx />');
    await repository.upsert(
      LocalActivityRecord(
        id: id,
        activityType: ActivityType.run,
        startedAt: DateTime.utc(2026, 6, 2, 10),
        endedAt: DateTime.utc(2026, 6, 2, 10, 30),
        elapsedDurationSeconds: 1800,
        distanceMeters: 5000,
        pointCount: 40,
        gpxFileName: fileName,
        uploadStatus: LocalActivityUploadStatus.pending,
        createdAt: DateTime.utc(2026, 6, 2, 10, 31),
        updatedAt: DateTime.utc(2026, 6, 2, 10, 31),
        connectionOrigin: 'https://example.test',
        connectionProfileId: 'profile-1',
      ),
    );
  }

  test('drain reports true while failed uploads remain', () async {
    await createPendingRecord();
    final queue = queueReturning(503);
    addTearDown(queue.dispose);
    final channel = BackgroundUploadChannel(queue: queue);

    final result = await channel.handleMethodCall(
      const MethodCall(BackgroundUploadChannel.drainMethod),
    );

    expect(result, isTrue);
  });

  test('drain reports false once the queue is settled', () async {
    await createPendingRecord();
    final queue = queueReturning(201);
    addTearDown(queue.dispose);
    final channel = BackgroundUploadChannel(queue: queue);

    final result = await channel.handleMethodCall(
      const MethodCall(BackgroundUploadChannel.drainMethod),
    );

    expect(result, isFalse);
  });

  test('rejects unknown methods', () async {
    final queue = queueReturning(201);
    addTearDown(queue.dispose);
    final channel = BackgroundUploadChannel(queue: queue);

    expect(
      () => channel.handleMethodCall(const MethodCall('other')),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
