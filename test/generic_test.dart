import 'package:angel_container/mirrors.dart';
import 'package:angel_couch/angel_couch.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:angel_framework/http.dart';
import 'package:couchdb/couchdb.dart';
import 'package:http/http.dart' as http;
import 'package:json_god/json_god.dart' as god;
import 'package:test/test.dart';

final headers = {
  'accept': 'application/json',
  'content-type': 'application/json'
};

final Map testGreeting = {'to': 'world'};

void wireHooked(HookedService hooked) {
  hooked.afterAll((HookedServiceEvent event) {
    print('Just ${event.eventName}: ${event.result}');
    print('Params: ${event.params}');
  });
  hooked.beforeCreated.listen((HookedServiceEvent event) {
    event.data['updatedAt'] = new DateTime.now().toIso8601String();
    event.data['createdAt'] = event.data['updatedAt'];
  });
  hooked.beforeUpdated.listen((HookedServiceEvent event) {
    event.data['updatedAt'] = new DateTime.now().toIso8601String();
  });
  hooked.beforeModified.listen((HookedServiceEvent event) {
    event.data['updatedAt'] = new DateTime.now().toIso8601String();
  });
}

void main() {
  group('Generic Tests', () {
//    Angel app;
    AngelHttp transport;
    http.Client client;
    final clientCouch = CouchDbClient(username: 'admin', password: 'admin');
    String testDbName = 'test_data';
//    await (print(Database(clientCouch).dbInfo('testData')));
//    final db = Database(clientCouch).createDb('angel_couch');
//    final doc = Document(clientCouch);
//    Db db = new Db('mongodb://localhost:27017/angel_mongo');
//    DbCollection testData;
    String url;
    HookedService<String, Map<String, dynamic>, CouchService> greetingService;

    setUp(() async {
      //app = new Angel();
      var reflector = const MirrorsReflector();
      var app = Angel(reflector: reflector);

      transport = AngelHttp(app);
      client = http.Client();
      try {
        await Database(clientCouch).deleteDb(testDbName);
      } catch (e) {}
      try {
        await Database(clientCouch).createDb(testDbName);
      } catch (e) {}
      //    }

// //      await db.open();
// //      testData = db.collection('test_data');
//       // Delete anything before we start
//       await testData.remove(<String, dynamic>{});

      var service = CouchService(clientCouch, testDbName,
          debug: true, allowRemoveAll: false);
      greetingService = HookedService(service);
      wireHooked(greetingService);

      app.use('/api', greetingService);

      await transport.startServer('127.0.0.1', 0);
      url = transport.uri.toString();
    });

    tearDown(() async {
      // Delete anything left over
//       await testData.remove(<String, dynamic>{});
//       await db.close();
      await transport.close();
      client = null;
      url = null;
      greetingService = null;
    });
/*     test('checks that database test_data does not exist', () async {
      CouchDbException error;
      try {
        await Database(clientCouch).dbInfo(testDbName);
      } on CouchDbException catch (e) {
        error = e;
      }
      expect(error.response.reason, equals('Database does not exist.'));
    });
 */
    test('query fields mapped to filters', () async {
      await greetingService.create({'foo': 'bar'});
      expect(
        await greetingService.index({
          'query': {'foo': 'not bar'}
        }),
        isEmpty,
      );
      expect(
        await greetingService.index(),
        isNotEmpty,
      );
    });

    test('insert items', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));

      response = await client.get('$url/api');
      expect(response.statusCode, isIn([200, 201]));
      var users = god.deserialize(response.body,
          outputType: <Map>[].runtimeType) as List<Map>;
      expect(users.length, equals(1));
    });

    test('read item', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;
      print('created $created');
      response = await client.get('$url/api/${created['_id']}');
      expect(response.statusCode, isIn([200, 201]));
      var read = god.deserialize(response.body) as Map;
      expect(read['_id'], equals(created['_id']));
      expect(read['to'], equals('world'));
      expect(read['createdAt'], isNot(null));
    });

    test('find One', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;
      var read = await greetingService
          .findOne({'query': where.id(created['_id'] as String)});
      expect(read['_id'], equals(created['_id']));
      expect(read['to'], equals('world'));
      expect(read['createdAt'], isNot(null));
    });

    test('readMany', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

//      var id = new ObjectId.fromHexString(created['id'] as String);
      var read = await greetingService.readMany([created['_id'] as String]);
      expect(read, [created]);
      //expect(read['createdAt'], isNot(null));
    });

    test('modify item', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      response = await client.patch('$url/api/${created['_id']}',
          body: god.serialize({'to': 'Mom'}), headers: headers);
      var modified = god.deserialize(response.body) as Map;
      expect(response.statusCode, isIn([200, 201]));
      expect(modified['_id'], equals(created['_id']));
      expect(modified['to'], equals('Mom'));
      expect(modified['updatedAt'], isNot(modified['createdAt']));
    });

    test('update item', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      expect(response.statusCode, isIn([200, 201]));
      var created = god.deserialize(response.body) as Map;

      response = await client.post('$url/api/${created['_id']}',
          body: god.serialize({'to': 'Updated'}), headers: headers);
      var modified = god.deserialize(response.body) as Map;
      expect(response.statusCode, isIn([200, 201]));
      expect(modified['_id'], equals(created['_id']));
      expect(modified['to'], equals('Updated'));
      expect(modified['updatedAt'], isNot(modified['createdAt']));
    });

    test('remove item', () async {
      var response = await client.post('$url/api',
          body: god.serialize(testGreeting), headers: headers);
      var created = god.deserialize(response.body) as Map;

      int lastCount = (await greetingService.index()).length;

      await client.delete('$url/api/${created['_id']}');
//      await client.delete('$url/api');
      expect((await greetingService.index()).length, equals(lastCount - 1));
    });

    test('cannot remove all unless explicitly set', () async {
      var response = await client.delete('$url/api/null');
      expect(response.statusCode, 403);
    });

    test('\$sort and query parameters', () async {
      // Search by where.eq
      Map world = await greetingService.create({'to': 'world'});
      Map mom = await greetingService.create({'to': 'Mom'});
      Map updated = await greetingService.create({'to': 'Updated'});

      var response = await client.get('$url/api?to=world');
      print(response.body);
      var queried = god.deserialize(response.body,
          outputType: <Map>[].runtimeType) as List<Map>;
      print('queried $queried');
      expect(queried.length, equals(1));
      expect(queried[0].keys.length, equals(5));
      expect(queried[0]['_id'], equals(world['_id']));
      expect(queried[0]['to'], equals(world['to']));
      expect(queried[0]['createdAt'], equals(world['createdAt']));

      response = await client.get('$url/api?\$sort.createdAt=-1');
      print(response.body);
      queried = god.deserialize(response.body, outputType: <Map>[].runtimeType)
          as List<Map>;

      expect(queried[0]['_id'], equals(updated['_id']));
      expect(queried[1]['_id'], equals(mom['_id']));
      expect(queried[2]['_id'], equals(world['_id']));

      queried = await greetingService.index({
        '\$query': {'_id': where.id(world['_id'] as String)}
      });
      print(queried);
      expect(queried.length, equals(1));
      expect(queried[0], equals(world));
    });
  });
}
