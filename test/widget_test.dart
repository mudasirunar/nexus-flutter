import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_theme.dart';
import 'package:nexus/shared/widgets/app_state_widgets.dart';

void main() {
  testWidgets('SyncStatusBadge renders all sync states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Column(
            children: [
              SyncStatusBadge(status: SyncRecordStatus.pending),
              SyncStatusBadge(status: SyncRecordStatus.syncing),
              SyncStatusBadge(status: SyncRecordStatus.synced),
              SyncStatusBadge(status: SyncRecordStatus.failed),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });
}
