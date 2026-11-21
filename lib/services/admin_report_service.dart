import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';
import '../utils/product_variant_utils.dart';

enum AdminReportScope {
  allProducts,
  productsWithPhotos,
  productsWithoutPhotos,
  bestSellers,
  users,
  topBuyers,
}

extension AdminReportScopeLabel on AdminReportScope {
  String get label => switch (this) {
    AdminReportScope.allProducts => 'Todos os produtos',
    AdminReportScope.productsWithPhotos => 'Produtos com foto',
    AdminReportScope.productsWithoutPhotos => 'Produtos sem foto',
    AdminReportScope.bestSellers => 'Mais vendidos',
    AdminReportScope.users => 'Todos os usuários',
    AdminReportScope.topBuyers => 'Usuários que mais compram',
  };
}

enum AdminReportFormat { text, pdf, docx }

class AdminReportEntry {
  const AdminReportEntry(this.title, this.lines);
  final String title;
  final List<String> lines;
}

class AdminReportData {
  const AdminReportData({
    required this.title,
    required this.entries,
    required this.generatedAt,
  });
  final String title;
  final List<AdminReportEntry> entries;
  final DateTime generatedAt;
  static const pageSize = 20;
  String get generatedLabel =>
      '${generatedAt.day.toString().padLeft(2, '0')}/${generatedAt.month.toString().padLeft(2, '0')}/${generatedAt.year} ${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}';
  String toText({int? page}) {
    final selected = page == null
        ? entries
        : entries.skip(page * pageSize).take(pageSize).toList();
    final out = StringBuffer(
      'CARRO DAS DELÍCIAS\n$title\nGerado em $generatedLabel\n${entries.length} registros\n\n',
    );
    if (entries.isEmpty) out.writeln('Nenhum registro encontrado.');
    for (var i = 0; i < selected.length; i++) {
      if (page == null && i % pageSize == 0) {
        out.writeln(
          '— Página ${i ~/ pageSize + 1} de ${(entries.length / pageSize).ceil()} —\n',
        );
      }
      final entry = selected[i];
      out.writeln('${i + 1 + (page ?? 0) * pageSize}. ${entry.title}');
      for (final line in entry.lines) {
        out.writeln(line);
      }
      out.writeln();
    }
    out.writeln(
      'Compras: pedidos pagos ou entregues. Pedidos de teste e cancelados não entram nos totais.',
    );
    return out.toString();
  }

  Map<String, dynamic> toWorkerData() => {
    'title': title,
    'generated': generatedLabel,
    'entries': entries
        .map((e) => {'title': e.title, 'lines': e.lines})
        .toList(),
  };
}

class AdminReportService {
  static int _cents(dynamic value) =>
      ((value is num ? value.toDouble() : double.tryParse('$value') ?? 0) * 100)
          .round();
  static String money(int cents) =>
      'R\$ ${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
  static bool isCountedOrder(Map<String, dynamic> order) {
    final status = '${order['status'] ?? ''}'.toLowerCase();
    if (order['is_teste'] == true ||
        status == 'teste' ||
        status.contains('cancel')) {
      return false;
    }
    return [
          'paid',
          'pago',
          'approved',
          'confirmado',
          'succeeded',
        ].contains('${order['payment_status']}'.toLowerCase()) ||
        ['entregue', 'concluido', 'concluído', 'completed'].contains(status) ||
        order['payment_confirmed_at'] != null;
  }

  static Future<AdminReportData> load(AdminReportScope scope) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null ||
        await client.rpc('current_user_is_admin') != true) {
      throw StateError('Somente administradores podem gerar relatórios.');
    }
    Future<List<Map<String, dynamic>>> pages(
      String table,
      String columns,
    ) async {
      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final chunk = await client
            .from(table)
            .select(columns)
            .order('id')
            .range(offset, offset + 499);
        rows.addAll(List<Map<String, dynamic>>.from(chunk));
        if (chunk.length < 500) return rows;
      }
    }

    final products = await pages('produtos', '*,categorias(nome)');
    final needsSales =
        scope == AdminReportScope.bestSellers ||
        scope == AdminReportScope.users ||
        scope == AdminReportScope.topBuyers;
    final orders = needsSales
        ? await pages(
            'pedidos',
            'id,user_id,total,status,payment_status,payment_confirmed_at,is_teste,created_at',
          )
        : <Map<String, dynamic>>[];
    final items = needsSales
        ? await pages(
            'pedido_itens',
            'id,pedido_id,produto_id,quantidade,preco_unitario,subtotal,tamanho_selecionado,sabor_selecionado',
          )
        : <Map<String, dynamic>>[];
    final users = <Map<String, dynamic>>[];
    if (scope == AdminReportScope.users ||
        scope == AdminReportScope.topBuyers) {
      for (var offset = 0; ; offset += 500) {
        final chunk = await client
            .rpc('get_all_users')
            .order('id')
            .range(offset, offset + 499);
        users.addAll(List<Map<String, dynamic>>.from(chunk));
        if ((chunk as List).length < 500) break;
      }
    }
    if (users.isNotEmpty) {
      final profiles = await pages(
        'profiles',
        'id,address,address_number,complement,neighborhood,city,cep,last_access_at,is_online',
      );
      final byId = {for (final profile in profiles) profile['id']: profile};
      for (var index = 0; index < users.length; index++) {
        users[index] = {...users[index], ...?byId[users[index]['id']]};
      }
    }
    return build(
      scope: scope,
      products: products,
      orders: orders,
      items: items,
      users: users,
    );
  }

  static AdminReportData build({
    required AdminReportScope scope,
    required List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> orders = const [],
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> users = const [],
    DateTime? generatedAt,
  }) {
    final counted = {
      for (final order in orders.where(isCountedOrder)) '${order['id']}': order,
    };
    final sales = <String, int>{}, revenue = <String, int>{};
    final userItems = <String, Map<String, int>>{};
    final names = {
      for (final product in products)
        '${product['id']}': '${product['nome'] ?? 'Produto'}',
    };
    for (final item in items) {
      final order = counted['${item['pedido_id']}'];
      if (order == null) continue;
      final productId = '${item['produto_id']}';
      final quantity = (item['quantidade'] as num?)?.toInt() ?? 0;
      sales.update(
        productId,
        (old) => old + quantity,
        ifAbsent: () => quantity,
      );
      final subtotal = item['subtotal'] != null
          ? _cents(item['subtotal'])
          : _cents(item['preco_unitario']) * quantity;
      revenue.update(
        productId,
        (old) => old + subtotal,
        ifAbsent: () => subtotal,
      );
      final bought = userItems.putIfAbsent('${order['user_id']}', () => {});
      final variants = [
        item['tamanho_selecionado'],
        item['sabor_selecionado'],
      ].whereType<String>().where((v) => v.isNotEmpty).join(' / ');
      final name =
          '${names[productId] ?? 'Produto $productId'}${variants.isEmpty ? '' : ' ($variants)'}';
      bought.update(name, (old) => old + quantity, ifAbsent: () => quantity);
    }
    final entries = <AdminReportEntry>[];
    if (scope == AdminReportScope.users ||
        scope == AdminReportScope.topBuyers) {
      final spent = <String, int>{}, orderCounts = <String, int>{};
      for (final order in counted.values) {
        final id = '${order['user_id']}';
        spent.update(
          id,
          (old) => old + _cents(order['total']),
          ifAbsent: () => _cents(order['total']),
        );
        orderCounts.update(id, (old) => old + 1, ifAbsent: () => 1);
      }
      final sorted =
          users
              .where(
                (u) =>
                    scope != AdminReportScope.topBuyers ||
                    (orderCounts['${u['id']}'] ?? 0) > 0,
              )
              .toList()
            ..sort(
              (a, b) => scope == AdminReportScope.topBuyers
                  ? (spent['${b['id']}'] ?? 0).compareTo(
                      spent['${a['id']}'] ?? 0,
                    )
                  : '${a['name'] ?? a['full_name']}'.toLowerCase().compareTo(
                      '${b['name'] ?? b['full_name']}'.toLowerCase(),
                    ),
            );
      for (final user in sorted) {
        final id = '${user['id']}';
        final bought = (userItems[id] ?? {}).entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        entries.add(
          AdminReportEntry('${user['name'] ?? user['full_name'] ?? 'Usuário'}', [
            'Email: ${user['email'] ?? 'Não informado'}',
            'Telefone: ${user['phone'] ?? 'Não informado'}',
            'Perfil: ${user['role'] ?? 'client'}',
            'Cadastro: ${user['created_at'] ?? 'Não informado'}',
            if (user['address'] != null)
              'Endereço: ${[user['address'], user['address_number'], user['complement'], user['neighborhood'], user['city'], user['cep']].whereType<String>().where((v) => v.trim().isNotEmpty).join(', ')}',
            if (user['last_access_at'] != null)
              'Último acesso: ${user['last_access_at']}',
            'Pedidos pagos/entregues: ${orderCounts[id] ?? 0}',
            'Total já gasto: ${money(spent[id] ?? 0)}',
            if (bought.isNotEmpty)
              'Produto mais comprado: ${bought.first.key} (${bought.first.value} un.)',
            ...bought.map((item) => 'Comprou: ${item.key} — ${item.value} un.'),
            if (bought.isEmpty) 'Nenhuma compra paga ou entregue.',
          ]),
        );
      }
    } else {
      final filtered =
          products
              .where(
                (p) => switch (scope) {
                  AdminReportScope.productsWithPhotos =>
                    AppSettingsService.hasProductPhoto(p),
                  AdminReportScope.productsWithoutPhotos =>
                    !AppSettingsService.hasProductPhoto(p),
                  AdminReportScope.bestSellers =>
                    p['mais_vendido'] == true || (sales['${p['id']}'] ?? 0) > 0,
                  _ => true,
                },
              )
              .toList()
            ..sort(
              (a, b) => scope == AdminReportScope.bestSellers
                  ? (sales['${b['id']}'] ?? 0).compareTo(
                      sales['${a['id']}'] ?? 0,
                    )
                  : '${a['nome']}'.toLowerCase().compareTo(
                      '${b['nome']}'.toLowerCase(),
                    ),
            );
      for (final product in filtered) {
        final photo =
            (product['imagem_url']?.toString().trim().isNotEmpty ?? false)
            ? '${product['imagem_url']}'
            : (product['imagens'] is List &&
                      (product['imagens'] as List).isNotEmpty
                  ? '${product['imagens'][0]}'
                  : 'Sem foto');
        entries.add(
          AdminReportEntry('${product['nome'] ?? 'Produto'}', [
            'Código: ${product['id']}',
            'Categoria: ${product['categoria_nome'] ?? product['categorias']?['nome'] ?? 'Sem categoria'}',
            product['preco'] == null
                ? 'Preço: conforme tamanho/sabor'
                : 'Preço: ${money(_cents(product['preco']))}',
            'Disponível: ${product['ativo'] == false ? 'Não' : 'Sim'}',
            if ((product['descricao']?.toString().trim() ?? '').isNotEmpty)
              'Descrição: ${product['descricao']}',
            for (final size in ProductVariantUtils.extractSizes(
              product['tamanhos'],
            ))
              'Tamanho: ${ProductVariantUtils.optionName(size)} - ${size['preco'] == null ? 'Consulte o preço' : money(_cents(size['preco']))}',
            for (final flavor in ProductVariantUtils.extractFlavors(
              product['sabores'],
            ))
              'Sabor: ${ProductVariantUtils.optionName(flavor)}${flavor['preco'] == null ? '' : ' - ${money(_cents(flavor['preco']))}'}',
            'Foto: $photo',
            'Mais vendido: ${product['mais_vendido'] == true ? 'Sim' : 'Não'}',
            'Novidade: ${product['novidade'] == true ? 'Sim' : 'Não'}',
            'Desconto: ${money(_cents(product['valor_desconto']))}',
            if (scope == AdminReportScope.bestSellers) ...[
              'Quantidade vendida: ${sales['${product['id']}'] ?? 0}',
              'Total em produtos: ${money(revenue['${product['id']}'] ?? 0)}',
            ],
          ]),
        );
      }
    }
    return AdminReportData(
      title: scope.label,
      entries: entries,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }

  static Future<Uint8List> createBytes(
    AdminReportData report,
    AdminReportFormat format,
  ) async {
    if (format == AdminReportFormat.text) {
      return Uint8List.fromList(utf8.encode(report.toText()));
    }
    final data = report.toWorkerData();
    if (format == AdminReportFormat.pdf) {
      final font = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      data['font'] = font.buffer.asUint8List(
        font.offsetInBytes,
        font.lengthInBytes,
      );
      final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      data['fontBold'] = bold.buffer.asUint8List(
        bold.offsetInBytes,
        bold.lengthInBytes,
      );
      return compute(_buildPdf, data);
    }
    return compute(_buildDocx, data);
  }

  static Future<XFile> createFile(
    AdminReportData report,
    AdminReportFormat format,
  ) async {
    final bytes = await createBytes(report, format);
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/admin_reports',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/relatorio_${DateTime.now().millisecondsSinceEpoch}.${format.name}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return XFile(
      file.path,
      mimeType: format == AdminReportFormat.pdf
          ? 'application/pdf'
          : format == AdminReportFormat.docx
          ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          : 'text/plain',
    );
  }
}

List<String> _chunks(String text) {
  final clean = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  return [
    for (var i = 0; i < clean.length; i += 800)
      clean.substring(i, (i + 800).clamp(0, clean.length)),
  ];
}

Future<Uint8List> _buildPdf(Map<String, dynamic> data) async {
  final document = pw.Document(
    title: data['title'] as String,
    author: 'Carro das Delícias',
  );
  final font = pw.Font.ttf(ByteData.sublistView(data['font'] as Uint8List));
  final entries = data['entries'] as List;
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 10000,
      theme: pw.ThemeData.withFont(
        base: font,
        bold: pw.Font.ttf(ByteData.sublistView(data['fontBold'] as Uint8List)),
      ),
      margin: const pw.EdgeInsets.all(36),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        color: PdfColors.black,
        child: pw.Text(
          'CARRO DAS DELÍCIAS — ${data['title']}',
          style: pw.TextStyle(color: PdfColors.white, fontSize: 14),
        ),
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${data['generated']}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.SizedBox(height: 16),
        pw.Text(
          '${entries.length} registros',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 8),
        if (entries.isEmpty) pw.Text('Nenhum registro encontrado.'),
        for (final entry in entries) ...[
          for (final chunk in _chunks('${entry['title']}'))
            pw.Text(
              chunk,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
          pw.SizedBox(height: 4),
          for (final line in entry['lines'] as List)
            for (final chunk in _chunks('$line'))
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(chunk, style: const pw.TextStyle(fontSize: 10)),
              ),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
        ],
        pw.Text(
          'Totais de compras: pedidos pagos ou entregues, excluindo testes e cancelamentos.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  return document.save();
}

Uint8List _buildDocx(Map<String, dynamic> data) {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  String escape(String value) => const HtmlEscape(
    HtmlEscapeMode.element,
  ).convert(value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''));
  String paragraph(String text, {bool heading = false}) =>
      '<w:p><w:pPr><w:spacing w:after="100"/>${heading ? '<w:keepNext/>' : ''}</w:pPr><w:r><w:rPr>${heading ? '<w:b/><w:sz w:val="26"/>' : '<w:sz w:val="21"/>'}</w:rPr><w:t xml:space="preserve">${escape(text)}</w:t></w:r></w:p>';
  final body = StringBuffer()
    ..write(paragraph('CARRO DAS DELÍCIAS', heading: true))
    ..write(paragraph('${data['title']}', heading: true))
    ..write(paragraph('Gerado em ${data['generated']}'));
  final entries = data['entries'] as List;
  if (entries.isEmpty) body.write(paragraph('Nenhum registro encontrado.'));
  for (var i = 0; i < entries.length; i++) {
    if (i > 0 && i % AdminReportData.pageSize == 0) {
      body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }
    final entry = entries[i] as Map;
    body.write(paragraph('${i + 1}. ${entry['title']}', heading: true));
    for (final line in entry['lines'] as List) {
      for (final chunk in _chunks('$line')) {
        body.write(paragraph(chunk));
      }
    }
    body.write(paragraph(''));
  }
  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
  );
  add(
    'word/_rels/document.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>',
  );
  add(
    'word/footer1.xml',
    '<?xml version="1.0" encoding="UTF-8"?><w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="right"/></w:pPr><w:r><w:t xml:space="preserve">Página </w:t></w:r><w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple><w:r><w:t xml:space="preserve"> de </w:t></w:r><w:fldSimple w:instr="NUMPAGES"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>',
  );
  add(
    'word/document.xml',
    '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>$body<w:sectPr><w:footerReference w:type="default" r:id="rId1"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
