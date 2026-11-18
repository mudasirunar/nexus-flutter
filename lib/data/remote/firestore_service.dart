import 'package:cloud_firestore/cloud_firestore.dart';

/// Abstraction over remote Firestore operations for testability.
abstract class RemoteSyncDataSource {
  Future<void> upsertDocument({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
  });

  Future<List<Map<String, dynamic>>> fetchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  });

  Stream<List<Map<String, dynamic>>> watchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  });
}

/// Cloud Firestore implementation of [RemoteSyncDataSource].
class FirestoreService implements RemoteSyncDataSource {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> upsertDocument({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    await _firestore
        .collection(collection)
        .doc(docId)
        .set(data, SetOptions(merge: true));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  }) async {
    final snapshot = await _firestore
        .collection(collection)
        .where('updatedAt', isGreaterThan: sinceEpochMs)
        .orderBy('updatedAt')
        .get();

    return _docsToMaps(snapshot.docs);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  }) {
    return _firestore
        .collection(collection)
        .where('updatedAt', isGreaterThan: sinceEpochMs)
        .orderBy('updatedAt')
        .snapshots()
        .map((snapshot) => _docsToMaps(snapshot.docs));
  }

  List<Map<String, dynamic>> _docsToMaps(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] ??= doc.id;
      return data;
    }).toList();
  }
}
