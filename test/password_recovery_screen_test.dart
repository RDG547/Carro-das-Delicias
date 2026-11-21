import 'dart:convert';
import 'package:carrodasdelicias/screens/password_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  bool rejectCode = false;
  final user = <String, dynamic>{
    'id': '00000000-0000-4000-8000-000000000001',
    'aud': 'authenticated',
    'email': 'cliente@example.test',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-11-20T12:00:00Z',
  };
  Map<String, dynamic> session() => {
    'access_token': 'test-access-token',
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': user,
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://auth.example.test',
      anonKey: 'test-key',
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryPkceStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object response = {};
        var status = 200;
        if (path.endsWith('/verify')) {
          if (rejectCode) {
            status = 400;
            response = {
              'code': 'otp_expired',
              'msg': 'Token has expired or is invalid',
            };
          } else {
            response = session();
          }
        } else if (path.endsWith('/token')) {
          response = session();
        } else if (path.endsWith('/user')) {
          response = user;
        }
        return http.Response(
          jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    rejectCode = false;
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String text) async {
    final button = find
        .ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        )
        .first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'cliente@example.test',
    );
    await press(tester, 'Enviar email');
  }

  testWidgets('recuperação exige código válido antes de salvar nova senha', (
    tester,
  ) async {
    await open(tester, const PasswordRecoveryScreen());
    await send(tester);
    final recover = requests.singleWhere(
      (r) => r.url.path.endsWith('/recover'),
    );
    expect(recover.url.queryParameters['redirect_to'], AuthEmailLinks.callback);
    expect(jsonDecode(recover.body)['email'], 'cliente@example.test');
    expect(find.text('Nova senha'), findsNothing);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await press(tester, 'Confirmar código');
    final verify = requests.singleWhere((r) => r.url.path.endsWith('/verify'));
    expect(jsonDecode(verify.body)['type'], 'recovery');
    await tester.enterText(
      find.byKey(const ValueKey('password_field_recovery_new')),
      'NovaSenha123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password_field_recovery_confirm')),
      'Diferente123',
    );
    await press(tester, 'Salvar nova senha');
    expect(find.text('As senhas não coincidem.'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('password_field_recovery_confirm')),
      'NovaSenha123',
    );
    await press(tester, 'Salvar nova senha');
    expect(
      jsonDecode(
        requests.singleWhere((r) => r.method == 'PUT').body,
      )['password'],
      'NovaSenha123',
    );
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'código expirado mantém o formulário sem permissão para mudar senha',
    (tester) async {
      rejectCode = true;
      await open(tester, const PasswordRecoveryScreen());
      await send(tester);
      await tester.enterText(find.byType(TextFormField).last, '999999');
      await press(tester, 'Confirmar código');
      expect(find.text('Nova senha'), findsNothing);
      expect(find.text('Código do email'), findsOneWidget);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'alteração de senha autentica a senha atual antes da atualização',
    (tester) async {
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'cliente@example.test',
        password: 'Antiga123',
      );
      requests.clear();
      await open(tester, const PasswordRecoveryScreen(changePassword: true));
      await tester.enterText(
        find.byKey(const ValueKey('password_field_change_current')),
        'Antiga123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field_recovery_new')),
        'NovaSenha123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password_field_recovery_confirm')),
        'NovaSenha123',
      );
      await press(tester, 'Salvar nova senha');
      expect(requests.map((r) => r.url.path).toList(), [
        '/auth/v1/token',
        '/auth/v1/user',
      ]);
      expect(jsonDecode(requests.first.body)['password'], 'Antiga123');
      expect(Supabase.instance.client.auth.currentSession, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('confirmação de email usa código de cadastro', (tester) async {
    await open(
      tester,
      const EmailConfirmationScreen(email: 'cliente@example.test'),
    );
    await press(tester, 'Confirmar email');
    expect(requests, isEmpty);
    await tester.enterText(find.byType(TextField), '123456');
    await press(tester, 'Confirmar email');
    expect(jsonDecode(requests.single.body)['type'], 'signup');
    expect(
      Supabase.instance.client.auth.currentUser?.email,
      'cliente@example.test',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
