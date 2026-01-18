import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../services/cart_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import 'abacatepay_payment_screen.dart';
import 'stripe_payment_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cartService = CartService();

  // Controllers para os campos do formulário
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _cepController = TextEditingController();
  final _observacoesController = TextEditingController();

  String _metodoPagamento = 'pix'; // Padrão é PIX
  double _troco = 0.0;
  final _trocoController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingUserData = true;
  int _pedidosConcluidos = 0; // Contador de pedidos concluídos (reputação)

  @override
  void initState() {
    super.initState();
    _cartService.addListener(_onCartChanged);
    _loadUserData(); // Carregar dados do usuário automaticamente
    _loadReputacao(); // Carregar reputação do usuário
  }

  @override
  void dispose() {
    _cartService.removeListener(_onCartChanged);
    _nomeController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _cepController.dispose();
    _observacoesController.dispose();
    _trocoController.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Carregar dados do perfil do usuário
        final response = await Supabase.instance.client
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();

        if (response != null && mounted) {
          // Preencher campos automaticamente com dados do perfil
          _nomeController.text = response['name'] ?? '';
          _telefoneController.text = response['phone'] ?? '';

          // Se existir endereço salvo, preencher também
          if (response['address'] != null) {
            _enderecoController.text = response['address'] ?? '';
          }
          if (response['neighborhood'] != null) {
            _bairroController.text = response['neighborhood'] ?? '';
          }
          if (response['city'] != null) {
            _cidadeController.text = response['city'] ?? '';
          }
          if (response['cep'] != null) {
            _cepController.text = response['cep'] ?? '';
          }
        } else if (mounted) {
          // Se não existe perfil, tentar usar dados do auth
          final userMetadata = user.userMetadata;
          if (userMetadata != null) {
            _nomeController.text = userMetadata['name'] ?? '';
            _telefoneController.text = userMetadata['phone'] ?? '';
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
      // Não mostrar erro para o usuário, apenas log
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
        });
      }
    }
  }

  Future<void> _loadReputacao() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Contar pedidos concluídos (status = 'entregue')
        final response = await Supabase.instance.client
            .from('pedidos')
            .select('id')
            .eq('user_id', user.id)
            .eq('status', 'entregue');

        if (mounted) {
          setState(() {
            _pedidosConcluidos = (response as List).length;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar reputação: $e');
    }
  }

  Future<void> _saveUserAddress() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final addressData = {
        'id': user.id,
        'address': _enderecoController.text.trim(),
        'neighborhood': _bairroController.text.trim(),
        'city': _cidadeController.text.trim(),
        'zip_code': _cepController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Usar upsert para criar ou atualizar o perfil
      await Supabase.instance.client.from('profiles').upsert(addressData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Finalizar Pedido',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _cartService.isEmpty ? _buildEmptyCart() : _buildCheckoutForm(),
      bottomNavigationBar: _cartService.isEmpty ? null : _buildBottomBar(),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 120,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Carrinho vazio',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Adicione produtos ao carrinho\npara finalizar seu pedido',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutForm() {
    return Form(
      key: _formKey,
      child: ListView(
        addRepaintBoundaries: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          // Resumo do pedido
          RepaintBoundary(child: _buildOrderSummary()),
          const SizedBox(height: 24),

          // Dados do cliente
          RepaintBoundary(child: _buildCustomerDataSection()),
          const SizedBox(height: 24),

          // Endereço de entrega
          RepaintBoundary(child: _buildDeliveryAddressSection()),
          const SizedBox(height: 24),

          // Método de pagamento
          RepaintBoundary(child: _buildPaymentMethodSection()),
          const SizedBox(height: 24),

          // Observações
          RepaintBoundary(child: _buildObservationsSection()),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Resumo do Pedido',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...(_cartService.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.quantidade}x ${item.nome}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(item.subtotal),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    if (item.tamanhoSelecionado != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Tamanho: ${_formatTamanho(item.tamanhoSelecionado!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )),

            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  CurrencyFormatter.format(_cartService.total),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerDataSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Dados do Cliente',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                const Spacer(),
                if (_isLoadingUserData)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue[700],
                    ),
                  )
                else if (_nomeController.text.isNotEmpty)
                  Icon(Icons.check_circle, color: Colors.green[600], size: 20),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome completo *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Nome é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _telefoneController,
              decoration: const InputDecoration(
                labelText: 'Telefone *',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
                hintText: '(11) 99999-9999',
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _PhoneInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Telefone é obrigatório';
                }
                final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
                if (digitsOnly.length < 10) {
                  return 'Telefone deve ter pelo menos 10 dígitos';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryAddressSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Endereço de Entrega',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _enderecoController,
              decoration: const InputDecoration(
                labelText: 'Endereço completo *',
                prefixIcon: Icon(Icons.home),
                border: OutlineInputBorder(),
                hintText: 'Rua, número, complemento',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Endereço é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _bairroController,
                    decoration: const InputDecoration(
                      labelText: 'Bairro *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Bairro é obrigatório';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _cepController,
                    decoration: const InputDecoration(
                      labelText: 'CEP',
                      border: OutlineInputBorder(),
                      hintText: '00000-000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _CepInputFormatter(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _cidadeController,
              decoration: const InputDecoration(
                labelText: 'Cidade *',
                prefixIcon: Icon(Icons.location_city),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Cidade é obrigatória';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    final bool podeUsarDinheiro = _pedidosConcluidos >= 5;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Text(
                  'Método de Pagamento',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // PIX - Sempre disponível
            InkWell(
              onTap: () {
                setState(() {
                  _metodoPagamento = 'pix';
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _metodoPagamento == 'pix'
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _metodoPagamento == 'pix'
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _metodoPagamento == 'pix'
                              ? Theme.of(context).primaryColor
                              : Colors.grey,
                          width: 2,
                        ),
                        color: _metodoPagamento == 'pix'
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                      ),
                      child: _metodoPagamento == 'pix'
                          ? const Icon(
                              Icons.circle,
                              size: 12,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Image.network(
                            'https://img.icons8.com/color/48/pix.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.payment, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'PIX',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Cartão de Crédito - Sempre disponível
            InkWell(
              onTap: () {
                setState(() {
                  _metodoPagamento = 'credito';
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _metodoPagamento == 'credito'
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _metodoPagamento == 'credito'
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _metodoPagamento == 'credito'
                              ? Theme.of(context).primaryColor
                              : Colors.grey,
                          width: 2,
                        ),
                        color: _metodoPagamento == 'credito'
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                      ),
                      child: _metodoPagamento == 'credito'
                          ? const Icon(
                              Icons.circle,
                              size: 12,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Image.network(
                            'https://img.icons8.com/color/48/bank-card-back-side.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.credit_card, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Cartão de Crédito',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Dinheiro - Requer 5 pedidos concluídos
            Opacity(
              opacity: podeUsarDinheiro ? 1.0 : 0.5,
              child: InkWell(
                onTap: podeUsarDinheiro
                    ? () {
                        setState(() {
                          _metodoPagamento = 'dinheiro';
                        });
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '🔒 Você precisa de 5 pedidos concluídos para pagar em dinheiro. Progresso: $_pedidosConcluidos/5',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _metodoPagamento == 'dinheiro' && podeUsarDinheiro
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _metodoPagamento == 'dinheiro' && podeUsarDinheiro
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                _metodoPagamento == 'dinheiro' &&
                                    podeUsarDinheiro
                                ? Theme.of(context).primaryColor
                                : Colors.grey,
                            width: 2,
                          ),
                          color:
                              _metodoPagamento == 'dinheiro' && podeUsarDinheiro
                              ? Theme.of(context).primaryColor
                              : Colors.transparent,
                        ),
                        child:
                            _metodoPagamento == 'dinheiro' && podeUsarDinheiro
                            ? const Icon(
                                Icons.circle,
                                size: 12,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Image.network(
                                  'https://img.icons8.com/material/24/wallet--v1.png',
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.payments, size: 24),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Dinheiro',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (!podeUsarDinheiro) ...[
                                  const SizedBox(width: 8),
                                  const Text(
                                    '🔒',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              podeUsarDinheiro
                                  ? 'Pagamento na entrega'
                                  : 'Requer $_pedidosConcluidos/5 pedidos concluídos',
                              style: TextStyle(
                                fontSize: 14,
                                color: podeUsarDinheiro
                                    ? Colors.grey
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_metodoPagamento == 'dinheiro' && podeUsarDinheiro) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  controller: _trocoController,
                  decoration: InputDecoration(
                    labelText: 'Troco para quanto?',
                    border: const OutlineInputBorder(),
                    hintText: 'Ex: R\$ 50,00',
                    helperText:
                        'Total: ${CurrencyFormatter.format(_cartService.total)}',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _CurrencyInputFormatter(),
                  ],
                  onChanged: (value) {
                    final numericValue = double.tryParse(
                      value
                          .replaceAll('R\$ ', '')
                          .replaceAll(',', '.')
                          .replaceAll('.', ''),
                    );
                    if (numericValue != null) {
                      _troco = numericValue / 100;
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildObservationsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Observações',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _observacoesController,
              decoration: const InputDecoration(
                labelText: 'Observações gerais do pedido',
                border: OutlineInputBorder(),
                hintText: 'Ex: Entregar no portão, campainha não funciona...',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total do Pedido:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  CurrencyFormatter.format(_cartService.total),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _finalizarPedido,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Confirmar Pedido',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizarPedido() async {
    // Validação explícita dos campos obrigatórios
    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Por favor, preencha seu nome completo')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_telefoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Por favor, preencha seu telefone')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_enderecoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Por favor, preencha o endereço de entrega'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_bairroController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Por favor, preencha o bairro')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_cidadeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Por favor, preencha a cidade')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validação do formulário (campos com validators)
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Por favor, corrija os campos destacados em vermelho',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validação adicional para troco
    if (_metodoPagamento == 'dinheiro' &&
        _troco > 0 &&
        _troco < _cartService.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O valor para troco deve ser maior que o total do pedido',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Obter usuário atual
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }

      // Para PIX e crédito, processar pagamento ANTES de criar pedido
      if (_metodoPagamento == 'pix') {
        // Navegar para tela de pagamento PIX
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (context) => AbacatePayPaymentScreen(
              pedidoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
              amount: _cartService.total,
              description: 'Pedido - Carro das Delícias',
            ),
          ),
        );

        // Se usuário cancelou ou pagamento falhou, retornar
        if (result == null || result['success'] != true) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }

        // Pagamento confirmado, continuar com criação do pedido
        debugPrint('✅ Pagamento PIX confirmado!');
      } else if (_metodoPagamento == 'credito') {
        // Navegar para tela de pagamento Stripe
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (context) => StripePaymentScreen(
              pedidoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
              amount: _cartService.total,
              description: 'Pedido - Carro das Delícias',
              customerEmail: user.email ?? '',
            ),
          ),
        );

        // Se usuário cancelou ou pagamento falhou, retornar
        if (result == null || result['success'] != true) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }

        // Pagamento confirmado, continuar com criação do pedido
        debugPrint('✅ Pagamento com cartão confirmado!');
      }

      // Dados do pedido
      final pedidoData = {
        'user_id': user.id, // ID do usuário autenticado
        'cliente_nome': _nomeController.text.trim(),
        'cliente_telefone': _telefoneController.text.trim(),
        'endereco_completo': _enderecoController.text.trim(),
        'bairro': _bairroController.text.trim(),
        'cidade': _cidadeController.text.trim(),
        'cep': _cepController.text.trim().isEmpty
            ? null
            : _cepController.text.trim(),
        'metodo_pagamento': _metodoPagamento,
        'valor_troco': _metodoPagamento == 'dinheiro' && _troco > 0
            ? _troco
            : null,
        'total': _cartService.total,
        'status': (_metodoPagamento == 'pix' || _metodoPagamento == 'credito')
            ? 'pago'
            : 'pendente',
        'observacoes': _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      // Inserir pedido no Supabase
      debugPrint('📦 Criando pedido no Supabase...');
      final response = await Supabase.instance.client
          .from('pedidos')
          .insert(pedidoData)
          .select()
          .single();

      final pedidoId = response['id'];
      debugPrint('✅ Pedido criado com sucesso! ID: $pedidoId');

      // Inserir itens do pedido
      final itens = _cartService.items.map((item) {
        debugPrint('📦 Item para salvar: ${item.nome}');
        debugPrint('   - Tamanho: ${item.tamanhoSelecionado}');
        debugPrint('   - Preço: ${item.preco}');
        debugPrint('   - Quantidade: ${item.quantidade}');
        return {
          'pedido_id': pedidoId,
          'produto_id': int.parse(item.id),
          'quantidade': item.quantidade,
          'preco_unitario': item.preco,
          'subtotal': item.subtotal,
          'observacoes': item.observacoes,
          'tamanho_selecionado': item.tamanhoSelecionado,
        };
      }).toList();

      debugPrint('📦 Inserindo ${itens.length} itens do pedido...');
      debugPrint('📦 Itens completos: $itens');
      await Supabase.instance.client.from('pedido_itens').insert(itens);
      debugPrint('✅ Itens do pedido inseridos com sucesso!');

      // Notificar admins sobre novo pedido
      try {
        debugPrint('📢 Notificando admins sobre pedido #$pedidoId...');
        await NotificationService.notifyAdminsNewOrder(
          orderId: pedidoId,
          customerName: _nomeController.text.trim(),
          total: _cartService.total,
        );
        debugPrint('✅ Admins notificados sobre pedido #$pedidoId');
      } catch (e) {
        debugPrint('⚠️ Erro ao notificar admins: $e');
        // Não falhar o pedido por causa disso
      }

      // Salvar dados do endereço no perfil para próximas compras
      try {
        await _saveUserAddress();
      } catch (e) {
        debugPrint('Erro ao salvar endereço: $e');
        // Não falhar o pedido por causa disso
      }

      if (mounted) {
        // Salvar total antes de limpar o carrinho
        final totalPedido = _cartService.total;

        // Limpar carrinho após criar pedido
        await _cartService.clearCart();

        if (!mounted) return;

        // Mostrar mensagem de sucesso
        _showSuccessDialog(response, totalPedido);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> pedido, double totalPedido) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 28),
            const SizedBox(width: 12),
            const Text('Pedido Confirmado!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seu pedido #${pedido['id'].toString().padLeft(4, '0')} foi registrado com sucesso!',
            ),
            const SizedBox(height: 12),
            Text('Total: ${CurrencyFormatter.format(totalPedido)}'),
            Text('Pagamento: ${_getPaymentMethodName(_metodoPagamento)}'),
            const SizedBox(height: 12),
            const Text(
              'Entraremos em contato em breve para confirmar a entrega.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // Fechar diálogo
              Navigator.of(context).pop();

              // Voltar para a tela principal (MainScreen)
              // Usar popUntil para remover todas as rotas até a primeira
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method) {
      case 'dinheiro':
        return 'Dinheiro';
      case 'debito':
        return 'Cartão de Débito';
      case 'credito':
        return 'Cartão de Crédito';
      case 'pix':
        return 'PIX';
      default:
        return method;
    }
  }

  String _formatTamanho(String tamanhoJson) {
    try {
      final tamanho = json.decode(tamanhoJson);
      if (tamanho is Map<String, dynamic>) {
        return tamanho['nome'] ?? tamanhoJson;
      }
      return tamanhoJson;
    } catch (e) {
      return tamanhoJson;
    }
  }
}

// Formatadores de entrada
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.length <= 11) {
      if (newText.length <= 2) {
        return newValue.copyWith(text: newText);
      } else if (newText.length <= 6) {
        return newValue.copyWith(
          text: '(${newText.substring(0, 2)}) ${newText.substring(2)}',
          selection: TextSelection.collapsed(offset: newText.length + 3),
        );
      } else if (newText.length <= 10) {
        return newValue.copyWith(
          text:
              '(${newText.substring(0, 2)}) ${newText.substring(2, 6)}-${newText.substring(6)}',
          selection: TextSelection.collapsed(offset: newText.length + 4),
        );
      } else {
        return newValue.copyWith(
          text:
              '(${newText.substring(0, 2)}) ${newText.substring(2, 7)}-${newText.substring(7, 11)}',
          selection: TextSelection.collapsed(offset: 15),
        );
      }
    }
    return oldValue;
  }
}

class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.length <= 8) {
      if (newText.length <= 5) {
        return newValue;
      } else {
        return newValue.copyWith(
          text: '${newText.substring(0, 5)}-${newText.substring(5)}',
          selection: TextSelection.collapsed(offset: newText.length + 1),
        );
      }
    }
    return oldValue;
  }
}

class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (newText.isEmpty) {
      return const TextEditingValue(
        text: 'R\$ 0,00',
        selection: TextSelection.collapsed(offset: 7),
      );
    }

    double value = double.parse(newText) / 100;
    String formatted = 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
