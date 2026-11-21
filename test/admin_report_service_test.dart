import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:carrodasdelicias/services/admin_report_service.dart';
import 'package:carrodasdelicias/services/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final products = <Map<String, dynamic>>[
    {
      'id': 1,
      'nome': 'Bolo & Café <Especial>',
      'preco': 12.5,
      'imagem_url': 'https://example.test/bolo.jpg',
    },
    {'id': 2, 'nome': 'Cenoura', 'preco': 10, 'imagens': []},
    {
      'id': 3,
      'nome': 'Chocolate',
      'preco': 20,
      'imagens': ['https://example.test/chocolate.jpg'],
    },
  ];
  final orders = <Map<String, dynamic>>[
    {'id': 1, 'user_id': 'a', 'status': 'entregue', 'total': 25},
    {
      'id': 2,
      'user_id': 'a',
      'status': 'cancelado',
      'payment_status': 'paid',
      'total': 500,
    },
    {
      'id': 3,
      'user_id': 'a',
      'status': 'entregue',
      'is_teste': true,
      'total': 500,
    },
    {'id': 4, 'user_id': 'b', 'status': 'pendente', 'total': 500},
    {
      'id': 5,
      'user_id': 'b',
      'status': 'preparando',
      'payment_status': 'paid',
      'total': 40,
    },
  ];
  final items = <Map<String, dynamic>>[
    {'id': 1, 'pedido_id': 1, 'produto_id': 1, 'quantidade': 2, 'subtotal': 25},
    {
      'id': 2,
      'pedido_id': 2,
      'produto_id': 1,
      'quantidade': 40,
      'subtotal': 500,
    },
    {
      'id': 3,
      'pedido_id': 3,
      'produto_id': 1,
      'quantidade': 40,
      'subtotal': 500,
    },
    {
      'id': 4,
      'pedido_id': 4,
      'produto_id': 2,
      'quantidade': 50,
      'subtotal': 500,
    },
    {'id': 5, 'pedido_id': 5, 'produto_id': 3, 'quantidade': 2, 'subtotal': 40},
  ];
  final users = <Map<String, dynamic>>[
    {'id': 'a', 'name': 'Ana', 'email': 'ana@example.test'},
    {'id': 'b', 'name': 'Bruno', 'email': 'bruno@example.test'},
    {'id': 'c', 'name': 'Cris', 'email': 'cris@example.test'},
  ];
  AdminReportData report(AdminReportScope scope) => AdminReportService.build(
    scope: scope,
    products: products,
    orders: orders,
    items: items,
    users: users,
    generatedAt: DateTime(2026, 11, 20, 12),
  );
  test('filtros com/sem foto consideram a imagem principal e a galeria', () {
    expect(report(AdminReportScope.productsWithPhotos).entries.length, 2);
    expect(
      report(AdminReportScope.productsWithoutPhotos).entries.single.title,
      'Cenoura',
    );
  });
  test(
    'mais compradores usa pagamentos reais e ignora cancelamentos, testes e pendências',
    () {
      final result = report(AdminReportScope.topBuyers);
      expect(result.entries.map((entry) => entry.title), ['Bruno', 'Ana']);
      expect(result.entries.first.lines, contains('Total já gasto: R\$ 40,00'));
      expect(result.entries.last.lines, contains('Total já gasto: R\$ 25,00'));
      expect(
        result.entries.last.lines.any((line) => line.contains('2 un.')),
        isTrue,
      );
    },
  );
  test('relatório de todos os usuários inclui quem ainda não comprou', () {
    expect(report(AdminReportScope.users).entries.length, 3);
    expect(
      report(AdminReportScope.users).entries.last.lines,
      contains('Total já gasto: R\$ 0,00'),
    );
  });
  test(
    'visibilidade oculta produtos sem foto para usuários e preserva a visão admin',
    () {
      AppSettingsService.showProductsWithoutPhotos.value = false;
      expect(
        AppSettingsService.isProductVisible(products[1], isAdmin: false),
        isFalse,
      );
      expect(
        AppSettingsService.isProductVisible(products[1], isAdmin: true),
        isTrue,
      );
      expect(
        AppSettingsService.isProductVisible(products[2], isAdmin: false),
        isTrue,
      );
      AppSettingsService.showProductsWithoutPhotos.value = true;
    },
  );
  test('texto completo tem paginação e não descarta registros', () {
    final large = AdminReportService.build(
      scope: AdminReportScope.allProducts,
      products: List.generate(
        45,
        (i) => {'id': i + 1, 'nome': 'Produto $i', 'preco': 10},
      ),
    );
    expect(large.toText(), contains('Página 3 de 3'));
    expect(large.toText(page: 2), contains('45.'));
  });
  test('DOCX válido preserva acentos, escapa XML e inclui paginação', () async {
    final bytes = await AdminReportService.createBytes(
      report(AdminReportScope.allProducts),
      AdminReportFormat.docx,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    expect(xml, contains('Bolo &amp; Café &lt;Especial&gt;'));
    expect(archive.findFile('word/footer1.xml'), isNotNull);
  });
  test(
    'PDF e DOCX grandes são gerados com todos os registros para revisão visual',
    () async {
      final large = AdminReportService.build(
        scope: AdminReportScope.allProducts,
        products: List.generate(
          45,
          (i) => {
            'id': i + 1,
            'nome': 'Bolo de Cenoura $i',
            'preco': 12.5,
            'descricao':
                'Massa de cenoura com cobertura de chocolate. Produto artesanal.',
          },
        ),
        generatedAt: DateTime(2026, 11, 20, 12),
      );
      final pdf = await AdminReportService.createBytes(
        large,
        AdminReportFormat.pdf,
      );
      final docx = await AdminReportService.createBytes(
        large,
        AdminReportFormat.docx,
      );
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      const destination = String.fromEnvironment('REPORT_FIXTURE_DIRECTORY');
      if (destination.isNotEmpty) {
        await Directory(destination).create(recursive: true);
        await File('$destination/catalogo.pdf').writeAsBytes(pdf);
        await File('$destination/catalogo.docx').writeAsBytes(docx);
      }
    },
  );
}
