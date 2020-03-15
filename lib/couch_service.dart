part of angel_couch.services;

/// Manipulates data from CouchDB as Maps.
class CouchService extends Service<String, Map<String, dynamic>> {
  CouchDbClient client;
  String dbName;

  /// If set to `true`, clients can remove all items by passing a `null` `id` to `remove`.
  ///
  /// `false` by default.
  final bool allowRemoveAll;

  /// If set to `true`, parameters in `req.query` are applied to the database query.
  final bool allowQuery;

  /// No longer used. Will be removed by `2.1.0`.
  @deprecated
  final bool debug;

  CouchService(this.client, this.dbName,
      {this.allowRemoveAll = false, this.allowQuery = true, this.debug = true})
      : super();

  SelectorBuilder _makeQuery([Map<String, dynamic> params_]) {
    Map params = new Map.from(params_ ?? {});
    params = params..remove('provider');
    SelectorBuilder result = where.exists('_id');

    // You can pass a SelectorBuilder as 'query';
    if (params['query'] is SelectorBuilder) {
      return params['query'] as SelectorBuilder;
    }

    for (var key in params.keys) {
      if (key == r'$sort' ||
          key == r'$query' &&
              (allowQuery == true || !params.containsKey('provider'))) {
        if (params[key] is Map) {
          // If they send a map, then we'll sort by every key in the map
          for (String fieldName in params[key].keys.where((x) => x is String)) {
            var sorter = params[key][fieldName];
            if (sorter is num) {
              result = result.sortBy(fieldName, descending: sorter == -1);
            } else if (sorter is String) {
              result = result.sortBy(fieldName, descending: sorter == "-1");
            } else if (sorter is SelectorBuilder) {
              result = result.and(sorter);
            }
          }
        } else if (params[key] is String && key == r'$sort') {
          // If they send just a string, then we'll sort
          // by that, ascending
          result = result.sortBy(params[key] as String);
          print('sort $result');
        }
      } else if (key == 'query' &&
          (allowQuery == true || !params.containsKey('provider'))) {
        print('yes');
        var query = params[key] as Map;
        print(query);
        query?.forEach((key, v) {
          print('$key  $v');
          var value = v is Map<String, dynamic> ? _filterNoQuery(v) : v;

          if (!_NO_QUERY.contains(key) &&
              value is! RequestContext &&
              value is! ResponseContext) {
            result = result.and(where.eq(key as String, value));
          }
        });
      }
    }

    return result;
  }

  Map<String, dynamic> _jsonify(Map<String, dynamic> doc,
      [Map<String, dynamic> params]) {
    var result = <String, dynamic>{};

    for (var key in doc.keys) {
      var value = doc[key];
      if (value is ObjectId) {
        result[key] = value.toHexString();
      } else if (value is! RequestContext && value is! ResponseContext) {
        result[key] = value;
      }
    }

//    return _transformId(result);
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> index(
      [Map<String, dynamic> params]) async {
    print('INDEX $params');
    print(_makeQuery(params)._query);
    return (await Database(client).find(dbName, _makeQuery(params)._query))
        .docs
        .map((x) => _jsonify(x, params))
        .toList();
  }

//   static const String _NONCE_KEY = '__angel__mongo__nonce__key__';

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> data,
      [Map<String, dynamic> params]) async {
    var item = _removeSensitive(data);

    try {
      var insertDoc =
          await Document(client).insertDoc(dbName, ObjectId().toJson(), item);
      var result = await Document(client).doc(dbName, insertDoc.id);
//       var nonce = (await collection.db.getNonce())['nonce'] as String;
//       var result = await collection.findAndModify(
//           query: where.eq(_NONCE_KEY, nonce),
//           update: item,
//           returnNew: true,
//           upsert: true);
//      return _jsonify(result.doc);
      return _jsonify(result.doc, params);
    } catch (e, st) {
      throw AngelHttpException(e, stackTrace: st);
    }
  }

// NO USE FROM ANGEL SERVICE
  @override
  Future<Map<String, dynamic>> findOne(
      [Map<String, dynamic> params,
      String errorMessage =
          'No record was found matching the given query.']) async {
    print('FINDO');
    print(_makeQuery(params)._query);
    var found = await Database(client).find(dbName, _makeQuery(params)._query);
//    var found = await collection.findOne(_makeQuery(params));

    if (found == null) {
      throw new AngelHttpException.notFound(message: errorMessage);
    }

    return _jsonify(found.docs.first, params);
  }

  @override
  Future<Map<String, dynamic>> read(String id,
      [Map<String, dynamic> params]) async {
    ObjectId _id = _makeId(id);
    var found = await Document(client).doc(dbName, id);
    if (found == null) {
      throw AngelHttpException.notFound(
          message: 'No record found for ID ${_id.toHexString()}');
    }

    return _jsonify((found.doc), params);
  }

//   @override
//   Future<List<Map<String, dynamic>>> readMany(List<String> ids,
//       [Map<String, dynamic> params]) async {
//     var q = _makeQuery(params);
//     q = ids.fold(q, (q, id) => q.or(where.id(_makeId(id))));
//     return await (await collection.find(q))
//         .map((x) => _jsonify(x, params))
//         .toList();
//   }

  @override
  Future<Map<String, dynamic>> modify(String id, data,
      [Map<String, dynamic> params]) async {
    Map<String, dynamic> target;

    try {
      target = await read(id, params);
    } on AngelHttpException catch (e) {
      if (e.statusCode == 404)
        return await create(data, params);
      else
        rethrow;
    }

    var result = mergeMap([target, data]);
    try {
      var modified = await Document(client).insertDoc(dbName, id, result);
      var doc = await Document(client).doc(dbName, id);
      result = _jsonify(doc.doc, params);
      return result;
    } catch (e, st) {
      //printDebug(e, st, 'MODIFY');
      throw new AngelHttpException(e, stackTrace: st);
    }
  }

  @override
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data,
      [Map<String, dynamic> params]) async {
    Map<String, dynamic> target;

    try {
      target = await read(id, params);
    } on AngelHttpException catch (e) {
      if (e.statusCode == 404)
        return await create(data, params);
      else
        rethrow;
    }
    data['_rev'] = target['_rev'];

//    var result = mergeMap([target, data]);
    try {
      var modified = await Document(client).insertDoc(dbName, id, data);
      var doc = await Document(client).doc(dbName, id);
      var result = _jsonify(doc.doc, params);
      return result;
    } catch (e, st) {
      //printDebug(e, st, 'MODIFY');
      throw new AngelHttpException(e, stackTrace: st);
    }
  }

  @override
  Future<Map<String, dynamic>> remove(String id,
      [Map<String, dynamic> params]) async {
    if (id == null || id == 'null') {
      // Remove everything...
      if (!(allowRemoveAll == true ||
          params?.containsKey('provider') != true)) {
        throw AngelHttpException.forbidden(
            message: 'Clients are not allowed to delete all items.');
      } else {
        var alldocs = await Database(client).allDocs(dbName);
        var docs2remove = _prepareBulkDelete(alldocs.rows);
        var rm = await Database(client).insertBulkDocs(dbName, docs2remove);
        return {};
      }
    }
    try {
      var doc2remove = await Document(client).doc(dbName, id);
      var result = await Document(client).deleteDoc(dbName, id, doc2remove.rev);
      return _jsonify(result.doc, params);
    } catch (e, st) {
      //printDebug(e, st, 'REMOVE');
      throw AngelHttpException(e, stackTrace: st);
    }
  }
}
