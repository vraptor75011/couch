library angel_couch.services;

import 'dart:async';
import 'dart:convert';

import 'package:angel_framework/angel_framework.dart';
import 'package:bson/bson.dart';
import 'package:couchdb/couchdb.dart';
import 'package:merge_map/merge_map.dart';

part 'couch_service.dart';
part 'selector_builder.dart';

List<Map<String, dynamic>> _prepareBulkDelete(List<Map<String, dynamic>> docs) {
  print('preparebulk ${docs}');
  var result = docs.map((obj) => obj
    ..['_id'] = obj['id']
    ..remove('id')
    ..['_rev'] = (obj['value'])['rev']
    ..remove('value')
    ..['_deleted'] = true
    ..remove('key'));
//  print(result.toList());
  return result.toList();
}

Map<String, dynamic> _transformId(Map<String, dynamic> doc) {
  var result = Map<String, dynamic>.from(doc);
  result
    ..['id'] = doc['_id']
    ..remove('_id');

  return result;
}

Map<String, dynamic> _transformIdRev(Map<String, dynamic> doc) {
  var result = Map<String, dynamic>.from(doc);
  result
    ..['id'] = doc['_id']
    ..remove('_id')
    ..['rev'] = doc['_rev']
    ..remove('_rev');

  return result;
}

ObjectId _makeId(id) {
  try {
    return (id is ObjectId) ? id : ObjectId.fromHexString(id.toString());
  } catch (e) {
    throw AngelHttpException.badRequest();
  }
}

const List<String> _sensitiveFieldNames = [
  'id',
  '_id',
  'rev',
  '_rev'
//  'createdAt',
//  'updatedAt'
];

Map<String, dynamic> _removeSensitive(Map<String, dynamic> data) {
  return data.keys
      .where((k) => !_sensitiveFieldNames.contains(k))
      .fold({}, (map, key) => map..[key] = data[key]);
}

const List<String> _NO_QUERY = ['__requestctx', '__responsectx'];

Map<String, dynamic> _filterNoQuery(Map<String, dynamic> data) {
  return data.keys.fold({}, (map, key) {
    var value = data[key];

    if (_NO_QUERY.contains(key) ||
        value is RequestContext ||
        value is ResponseContext) return map;
    if (key is! Map) return map..[key] = value;
    return map..[key] = _filterNoQuery(value as Map<String, dynamic>);
  });
}
