import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso con lo justo para entrar y listar tres gastos en dos
/// categorías. No necesita el backend ni el emulador.
class _Servidor implements HttpClientAdapter {
  final gastos = [
    {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-24'},
    {'id': 2, 'descripcion': 'Taxi', 'monto': 3.25, 'categoria': 'transporte', 'fecha': '2026-10-24'},
    {'id': 3, 'descripcion': 'Cena', 'monto': 12.0, 'categoria': 'comida', 'fecha': '2026-10-24'},
  ];

  ResponseBody _json(Object cuerpo, int codigo) => ResponseBody.fromString(jsonEncode(cuerpo), codigo,
      headers: {Headers.contentTypeHeader: ['application/json']});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    if (o.path == '/usuarios/token') return _json({'access_token': 'tok-a@b.com', 'token_type': 'bearer'}, 200);
    if (o.path == '/usuarios/me') return _json({'id': 1, 'email': 'a@b.com'}, 200);
    if (o.path == '/gastos/categorias') {
      return _json({'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0}, 200);
    }
    if (o.path == '/gastos/' && o.method == 'GET') return _json(gastos, 200);
    return _json({'detail': 'ruta no prevista en la prueba: ${o.path}'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _esperar(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_filtro').path));

  testWidgets('el filtro por categoría muestra solo los gastos de comida y «Todas» los muestra todos', (tester) async {
    // Por qué `runAsync`: iniciar sesión y abrir la caja de Hive usan E/S real,
    // que no avanza dentro del reloj falso de las pruebas de widgets.
    late GastosController gastos;
    await tester.runAsync(() async {
      Get.reset();
      Get.testMode = true;
      await Hive.deleteFromDisk();
      FlutterSecureStorage.setMockInitialValues({});
      Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))..httpClientAdapter = _Servidor()));
      final auth = Get.put(AuthController());
      await _esperar(() => !auth.restaurando.value);
      await auth.iniciarSesion('a@b.com', 'clave-1234');
      gastos = Get.put(GastosController());
      await _esperar(() => gastos.gastos.length == 3 && gastos.estado.value.name == 'exito');
    });

    await tester.pumpWidget(const GetMaterialApp(home: GastosScreen()));
    await tester.pump();
    expect(find.text('Taxi'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'comida'));
    await tester.pump();
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pump();
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);

    await tester.runAsync(Hive.close);
  });
}
