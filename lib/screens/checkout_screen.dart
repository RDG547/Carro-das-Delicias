import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/cart_service.dart';
import '../services/app_settings_service.dart';
import '../services/delivery_geofence_service.dart';
import '../services/main_navigation_service.dart';
import '../services/notification_service.dart';
import '../services/order_payment_service.dart';
import '../utils/constants.dart';
import '../utils/product_action_helper.dart';
import '../utils/product_variant_utils.dart';
import 'abacatepay_payment_screen.dart';
import 'stripe_payment_screen.dart';
import '../widgets/d_plus_one_info_dialog.dart';
import '../widgets/category_icon_widget.dart';
import '../widgets/scroll_down_indicator.dart';

String _resolveCheckoutCategoryIcon(String? categoryName, dynamic rawIcon) {
  final name = categoryName?.trim();
  if (name != null && name.isNotEmpty) {
    final override = CategoryIconWidget.categoryIconOverrides[name];
    if (override != null) return override;

    final normalizedName = name.toLowerCase();
    for (final entry in CategoryIconWidget.categoryIconOverrides.entries) {
      final overrideName = entry.key.toLowerCase();
      if (normalizedName == overrideName ||
          normalizedName.contains(overrideName.replaceAll('s', '')) ||
          overrideName.contains(normalizedName.replaceAll('s', ''))) {
        return entry.value;
      }
    }
  }

  final icon = rawIcon?.toString().trim();
  if (icon != null && icon.isNotEmpty) return icon;

  return 'asset:assets/icons/todos_category.svg';
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _cartService = CartService();
  final _geofenceService = DeliveryGeofenceService.instance;
  final _scrollController = ScrollController();
  late AnimationController _scrollIndicatorController;
  bool _showScrollIndicator = true;
  bool _hasScrolledDown = false;
  bool _isScrollIndicatorAnimating = false;
  bool _keyboardVisible = false;

  // Controllers para os campos do formulário
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _complementoController = TextEditingController();
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
  DateTime? _dataEntrega; // Data agendada para entrega (null = D+1 padrão)
  bool _isPedidoTeste = false; // Pedido de teste (somente admin)
  bool _isAdmin = false; // Se o usuário logado é admin
  Timer? _deliveryAreaDebounce;
  bool _isCheckingDeliveryArea = false;
  bool _isUsingCurrentLocation = false;
  bool _isSelectingLocationOnMap = false;
  bool _isApplyingLocationAddress = false;
  DeliveryAddressValidation? _deliveryAreaValidation;
  CashPaymentSettings _cashPaymentSettings =
      const CashPaymentSettings.defaults();

  // Calcula a taxa de serviço baseada no método de pagamento
  double get _taxaServico {
    if (_isPedidoTeste) return 0.0;
    final subtotal = _cartService.total;
    switch (_metodoPagamento) {
      case 'pix':
        return 1.00;
      case 'credito':
        if (subtotal <= 0) return 0.0;
        final fee = (subtotal * 0.0399) + 0.39;
        return fee < 1.0 ? 1.0 : fee;
      default:
        return 0.0;
    }
  }

  // Total do pedido com taxa de serviço incluída
  double get _totalComTaxa => _cartService.total + _taxaServico;

  String get _cartItemCountLabel {
    final count = _cartService.totalItems;
    return '$count ${count == 1 ? 'item' : 'itens'}';
  }

  String _formatCep(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    if (digits.length > 5) {
      return '${digits.substring(0, 5)}-${digits.substring(5)}';
    }
    return digits;
  }

  void _hideScrollIndicator() {
    if (!_showScrollIndicator) return;

    _scrollIndicatorController.stop(canceled: true);
    _scrollIndicatorController.value = 0;
    setState(() => _showScrollIndicator = false);
  }

  void _startScrollIndicatorHint() {
    if (_isScrollIndicatorAnimating ||
        !_showScrollIndicator ||
        _hasScrolledDown) {
      return;
    }

    _isScrollIndicatorAnimating = true;
    unawaited(() async {
      try {
        while (mounted && _showScrollIndicator && !_hasScrolledDown) {
          await _scrollIndicatorController.forward(from: 0).orCancel;
          if (!mounted || !_showScrollIndicator || _hasScrolledDown) {
            break;
          }
          await _scrollIndicatorController.reverse().orCancel;
        }
      } on TickerCanceled {
        // Interrupcao esperada quando o indicador e ocultado.
      } finally {
        _isScrollIndicatorAnimating = false;
        if (mounted) {
          _scrollIndicatorController.value = 0;
        }
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardVisible = _isKeyboardVisibleFromWindow();
    _cartService.addListener(_onCartChanged);
    _addDeliveryAddressListeners();
    unawaited(_geofenceService.inicializarAreas());
    _loadUserData();
    _loadReputacao();
    _loadCashPaymentSettings();

    _scrollIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_hasScrolledDown) {
        _hasScrolledDown = true;
      }
      if (_scrollController.offset > 50 && _showScrollIndicator) {
        _hideScrollIndicator();
      }
    });

    // Mostrar popup informativo sobre entrega D+1
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        DPlusOneInfoDialog.show(context);
        _startScrollIndicatorHint();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deliveryAreaDebounce?.cancel();
    _removeDeliveryAddressListeners();
    _cartService.removeListener(_onCartChanged);
    _scrollController.dispose();
    _scrollIndicatorController.dispose();
    _nomeController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _cepController.dispose();
    _observacoesController.dispose();
    _trocoController.dispose();
    super.dispose();
  }

  bool _isKeyboardVisibleFromWindow() {
    return WidgetsBinding.instance.platformDispatcher.views.any(
      (view) => view.viewInsets.bottom > 0,
    );
  }

  @override
  void didChangeMetrics() {
    final keyboardVisible = _isKeyboardVisibleFromWindow();
    if (keyboardVisible == _keyboardVisible || !mounted) return;
    setState(() {
      _keyboardVisible = keyboardVisible;
    });
  }

  void _onCartChanged() {
    if (!mounted) return;

    if (_cartService.isEmpty && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_cartService.isEmpty || _isLoading) return;
        _leaveCheckoutForProducts();
      });
      return;
    }

    setState(() {});
  }

  void _addDeliveryAddressListeners() {
    _enderecoController.addListener(_scheduleDeliveryAreaValidation);
    _bairroController.addListener(_scheduleDeliveryAreaValidation);
    _cidadeController.addListener(_scheduleDeliveryAreaValidation);
    _cepController.addListener(_scheduleDeliveryAreaValidation);
  }

  void _removeDeliveryAddressListeners() {
    _enderecoController.removeListener(_scheduleDeliveryAreaValidation);
    _bairroController.removeListener(_scheduleDeliveryAreaValidation);
    _cidadeController.removeListener(_scheduleDeliveryAreaValidation);
    _cepController.removeListener(_scheduleDeliveryAreaValidation);
  }

  bool _hasEnoughAddressForDeliveryAreaValidation() {
    final cepDigits = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return _enderecoController.text.trim().isNotEmpty &&
        _bairroController.text.trim().isNotEmpty &&
        _cidadeController.text.trim().isNotEmpty &&
        cepDigits.length == 8;
  }

  String _deliveryAreaAddressQuery() {
    final cepDigits = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return [
      _enderecoController.text.trim(),
      _bairroController.text.trim(),
      _cidadeController.text.trim(),
      cepDigits,
    ].where((part) => part.isNotEmpty).join(', ');
  }

  void _scheduleDeliveryAreaValidation() {
    if (_isApplyingLocationAddress) return;

    _deliveryAreaDebounce?.cancel();

    if (!_hasEnoughAddressForDeliveryAreaValidation()) {
      if (_deliveryAreaValidation != null || _isCheckingDeliveryArea) {
        setState(() {
          _deliveryAreaValidation = null;
          _isCheckingDeliveryArea = false;
        });
      }
      return;
    }

    final currentQuery = _deliveryAreaAddressQuery();
    if (_deliveryAreaValidation?.addressQuery != currentQuery && mounted) {
      setState(() => _deliveryAreaValidation = null);
    }

    _deliveryAreaDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_validateDeliveryArea());
    });
  }

  Future<bool> _validateDeliveryArea({bool showDialogOnFailure = false}) async {
    if (_isPedidoTeste) return true;

    if (!_hasEnoughAddressForDeliveryAreaValidation()) {
      if (showDialogOnFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Preencha endereço, bairro, cidade e CEP para validar a área de entrega.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    final currentQuery = _deliveryAreaAddressQuery();
    final cachedValidation = _deliveryAreaValidation;
    if (cachedValidation != null &&
        cachedValidation.addressQuery == currentQuery &&
        cachedValidation.atende) {
      return true;
    }

    if (mounted) {
      setState(() => _isCheckingDeliveryArea = true);
    }

    final rawValidation = await _geofenceService.validarEndereco(
      endereco: _enderecoController.text,
      bairro: _bairroController.text,
      cidade: _cidadeController.text,
      cep: _cepController.text,
    );
    final validation = DeliveryAddressValidation(
      atende: rawValidation.atende,
      addressQuery: currentQuery,
      areaName: rawValidation.areaName,
      message: rawValidation.message,
      latitude: rawValidation.latitude,
      longitude: rawValidation.longitude,
    );

    if (!mounted) return false;

    setState(() {
      _deliveryAreaValidation = validation;
      _isCheckingDeliveryArea = false;
    });

    if (!validation.atende && showDialogOnFailure) {
      await _showDeliveryAreaUnavailableDialog(validation);
    }

    return validation.atende;
  }

  Future<void> _validateCurrentDeviceLocation() async {
    if (_isUsingCurrentLocation || _isCheckingDeliveryArea) return;

    setState(() => _isUsingCurrentLocation = true);

    try {
      final position = await _getCurrentDeliveryPosition();
      if (position == null) return;

      await _applyDeliveryCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
        insideMessage: 'Localização atual dentro da área de entrega.',
        outsideMessage: 'Sua localização atual está fora da área de entrega.',
      );
    } finally {
      if (mounted) {
        setState(() => _isUsingCurrentLocation = false);
      }
    }
  }

  Future<void> _openDeliveryMapPicker() async {
    if (_isSelectingLocationOnMap || _isCheckingDeliveryArea) return;

    final initialCenter = _initialDeliveryMapCenter();
    final selection = await Navigator.of(context).push<_DeliveryMapSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _DeliveryLocationPickerPage(
          initialLatitude: initialCenter.latitude,
          initialLongitude: initialCenter.longitude,
        ),
      ),
    );
    if (selection == null || !mounted) return;

    setState(() => _isSelectingLocationOnMap = true);
    try {
      await _applyDeliveryCoordinates(
        latitude: selection.latitude,
        longitude: selection.longitude,
        insideMessage: 'Ponto selecionado dentro da área de entrega.',
        outsideMessage: 'O ponto selecionado está fora da área de entrega.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSelectingLocationOnMap = false);
      }
    }
  }

  _DeliveryMapSelection _initialDeliveryMapCenter() {
    final validation = _deliveryAreaValidation;
    final latitude = validation?.latitude;
    final longitude = validation?.longitude;
    if (latitude != null && longitude != null) {
      return _DeliveryMapSelection(latitude: latitude, longitude: longitude);
    }

    return const _DeliveryMapSelection(latitude: -22.8809, longitude: -43.4656);
  }

  Future<void> _applyDeliveryCoordinates({
    required double latitude,
    required double longitude,
    required String insideMessage,
    required String outsideMessage,
  }) async {
    if (!mounted) return;

    setState(() {
      _isCheckingDeliveryArea = true;
      _deliveryAreaValidation = null;
    });

    try {
      await _geofenceService.inicializarAreas();
      final areaResult = _geofenceService.verificarCoordenada(
        latitude,
        longitude,
      );

      final reverseAddress = await _geofenceService.reverseGeocodeCoordinates(
        latitude: latitude,
        longitude: longitude,
      );
      if (reverseAddress?.hasAnyValue == true) {
        _applyReverseAddress(reverseAddress!);
      }

      if (!mounted) return;

      final validation = DeliveryAddressValidation(
        atende: areaResult.atende,
        addressQuery: _hasEnoughAddressForDeliveryAreaValidation()
            ? _deliveryAreaAddressQuery()
            : 'coord:$latitude,$longitude',
        areaName: areaResult.areaName,
        latitude: latitude,
        longitude: longitude,
        message: areaResult.atende ? insideMessage : outsideMessage,
      );

      setState(() {
        _deliveryAreaValidation = validation;
      });

      if (!validation.atende) {
        await _showDeliveryAreaUnavailableDialog(validation);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao validar a localização: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingDeliveryArea = false);
      }
    }
  }

  Future<Position?> _getCurrentDeliveryPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ative a localização do dispositivo para continuar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissão de localização negada.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissão de localização bloqueada'),
            content: const Text(
              'Ative a permissão de localização nas configurações do aplicativo para usar sua posição atual.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(Geolocator.openAppSettings());
                },
                child: const Text('Abrir configurações'),
              ),
            ],
          ),
        );
      }
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  void _applyReverseAddress(DeliveryReverseAddress address) {
    _isApplyingLocationAddress = true;
    try {
      if (address.endereco?.trim().isNotEmpty == true) {
        _enderecoController.text = address.endereco!.trim();
      }
      if (address.bairro?.trim().isNotEmpty == true) {
        _bairroController.text = address.bairro!.trim();
      }
      if (address.cidade?.trim().isNotEmpty == true) {
        _cidadeController.text = address.cidade!.trim();
      }
      if (address.cep?.trim().isNotEmpty == true) {
        _cepController.text = _formatCep(address.cep!.trim());
      }
    } finally {
      _isApplyingLocationAddress = false;
      _deliveryAreaDebounce?.cancel();
    }
  }

  Future<void> _showDeliveryAreaUnavailableDialog(
    DeliveryAddressValidation validation,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red[700]),
            const SizedBox(width: 10),
            const Expanded(child: Text('Fora da área de entrega')),
          ],
        ),
        content: Text(
          validation.message ??
              'Ainda não atendemos este endereço. Confira os dados informados ou escolha outro endereço.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Editar endereço'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryAreaValidationStatus() {
    final validation = _deliveryAreaValidation;

    Color color;
    IconData icon;
    String text;

    if (_isCheckingDeliveryArea) {
      color = Colors.blue;
      icon = Icons.sync;
      text = 'Verificando área de entrega...';
    } else if (validation == null) {
      color = Colors.grey;
      icon = Icons.info_outline;
      text =
          'Digite endereço, bairro, cidade e CEP para confirmar se atendemos à região.';
    } else if (validation.atende) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
      final areaName = validation.areaName;
      text = areaName == null || areaName.isEmpty
          ? 'Endereço dentro da área de entrega.'
          : 'Endereço dentro da área de entrega: $areaName.';
    } else {
      color = Colors.red;
      icon = Icons.location_off_outlined;
      text = validation.message ?? 'Ainda não entregamos neste endereço.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _isCheckingDeliveryArea
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color == Colors.grey ? Colors.grey[700] : color,
                fontSize: 12,
                fontWeight: validation?.atende == true
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _leaveCheckoutForProducts() {
    MainNavigationService.navigateToPage(0);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
          // Verificar se é admin
          _isAdmin = response['role'] == 'admin';
          // Preencher campos automaticamente com dados do perfil
          _nomeController.text = response['name'] ?? '';
          String phoneDigits = (response['phone'] ?? '').replaceAll(
            RegExp(r'[^\d]'),
            '',
          );
          if (phoneDigits.startsWith('55') && phoneDigits.length > 11) {
            phoneDigits = phoneDigits.substring(2);
          }
          _telefoneController.text = _PhoneInputFormatter.format(phoneDigits);

          // Se existir endereço salvo, preencher também
          if (response['address'] != null) {
            _enderecoController.text = response['address'] ?? '';
          }
          if (response['complement'] != null) {
            _complementoController.text = response['complement'] ?? '';
          }
          if (response['neighborhood'] != null) {
            _bairroController.text = response['neighborhood'] ?? '';
          }
          if (response['city'] != null) {
            _cidadeController.text = response['city'] ?? '';
          }
          if (response['cep'] != null) {
            _cepController.text = _formatCep(response['cep'] ?? '');
          }
        } else if (mounted) {
          // Se não existe perfil, tentar usar dados do auth
          final userMetadata = user.userMetadata;
          if (userMetadata != null) {
            _nomeController.text = userMetadata['name'] ?? '';
            String phoneDigits = (userMetadata['phone'] ?? '').replaceAll(
              RegExp(r'[^\d]'),
              '',
            );
            if (phoneDigits.startsWith('55') && phoneDigits.length > 11) {
              phoneDigits = phoneDigits.substring(2);
            }
            _telefoneController.text = _PhoneInputFormatter.format(phoneDigits);
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
            _syncCashPaymentAvailability();
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar reputação: $e');
    }
  }

  Future<void> _loadCashPaymentSettings() async {
    final settings = await AppSettingsService.getCashPaymentSettings();
    if (!mounted) return;

    setState(() {
      _cashPaymentSettings = settings;
      _syncCashPaymentAvailability();
    });
  }

  void _syncCashPaymentAvailability() {
    final isGuest = Supabase.instance.client.auth.currentUser == null;
    final canUseCash = _cashPaymentSettings.canUse(
      isGuest: isGuest,
      completedOrders: _pedidosConcluidos,
    );

    if (!canUseCash && _metodoPagamento == 'dinheiro') {
      _metodoPagamento = 'pix';
      _troco = 0.0;
      _trocoController.clear();
    }
  }

  Future<void> _saveUserAddress() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final addressData = <String, dynamic>{
      'address': _enderecoController.text.trim(),
      'complement': _complementoController.text.trim(),
      'neighborhood': _bairroController.text.trim(),
      'city': _cidadeController.text.trim(),
      'cep': _cepController.text.replaceAll(RegExp(r'[^0-9]'), ''),
      'updated_at': DateTime.now().toIso8601String(),
    };

    final typedName = _nomeController.text.trim();
    if (typedName.isNotEmpty) {
      addressData['name'] = typedName;
    }

    final typedPhone = _telefoneController.text.trim();
    if (typedPhone.isNotEmpty) {
      addressData['phone'] = typedPhone;
    }

    final supabase = Supabase.instance.client;
    final updated = await supabase
        .from('profiles')
        .update(addressData)
        .eq('id', user.id)
        .select('id')
        .limit(1);

    if (updated.isNotEmpty) return;

    await supabase.from('profiles').insert({
      ...addressData,
      'id': user.id,
      'name': _fallbackProfileName(user),
      'email': _fallbackProfileEmail(user),
    });
  }

  String _fallbackProfileName(User user) {
    final typedName = _nomeController.text.trim();
    if (typedName.isNotEmpty) return typedName;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    final metadataName = (metadata['full_name'] ?? metadata['name'])
        ?.toString()
        .trim();
    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    final emailName = user.email?.split('@').first.trim();
    if (emailName != null && emailName.isNotEmpty) return emailName;

    return 'Usuário';
  }

  String _fallbackProfileEmail(User user) {
    final email = user.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) return email;
    return 'sem-email-${user.id}@local.app';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Informação sobre entrega',
            onPressed: () => DPlusOneInfoDialog.show(context, forceShow: true),
          ),
        ],
      ),
      body: _cartService.isEmpty
          ? _buildEmptyCart()
          : Stack(
              children: [
                _buildCheckoutForm(keyboardVisible: _keyboardVisible),
                if (_showScrollIndicator && !_keyboardVisible)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: ScrollDownIndicator(
                      animation: _scrollIndicatorController,
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _cartService.isEmpty || _keyboardVisible
          ? null
          : _buildBottomBar(),
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

  Widget _buildCheckoutForm({required bool keyboardVisible}) {
    return Form(
      key: _formKey,
      child: ListView(
        controller: _scrollController,
        addRepaintBoundaries: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardVisible ? 0 : 16),
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

          // Agendamento de entrega
          RepaintBoundary(child: _buildScheduleSection()),
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

            ..._cartService.items.map(_buildCheckoutSummaryItem),

            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAddMoreItemsModal,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Adicionar mais itens'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green[700],
                  side: BorderSide(color: Colors.green[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal:', style: TextStyle(fontSize: 14)),
                Text(
                  CurrencyFormatter.format(_cartService.total),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            if (_taxaServico > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Taxa de serviço',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: _metodoPagamento == 'pix'
                            ? 'Taxa fixa de R\$ 1,00 para pagamento via PIX'
                            : 'Taxa de 3,99% + R\$ 0,39 para pagamento via cartão',
                        child: Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    CurrencyFormatter.format(_taxaServico),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  CurrencyFormatter.format(_totalComTaxa),
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

  Future<_CheckoutAddItemsCatalog> _loadCheckoutAddItemsCatalog() async {
    final supabase = Supabase.instance.client;
    final results = await Future.wait<dynamic>([
      supabase
          .from('categorias')
          .select('id, nome, icone')
          .order('ordem', ascending: true),
      supabase
          .from('produtos')
          .select('''
            *,
            categorias:categoria_id (
              id,
              nome,
              icone
            )
          ''')
          .order('nome', ascending: true),
    ]);

    final categories = List<Map<String, dynamic>>.from(
      (results[0] as List).map((category) {
        final normalized = Map<String, dynamic>.from(category as Map);
        final categoryName = normalized['nome']?.toString() ?? 'Categoria';
        return {
          ...normalized,
          'nome': categoryName,
          'icone': _resolveCheckoutCategoryIcon(
            categoryName,
            normalized['icone'],
          ),
        };
      }),
    );

    final products = List<Map<String, dynamic>>.from(
      (results[1] as List).map((product) {
        final normalized = Map<String, dynamic>.from(product as Map);
        final rawCategory = normalized['categorias'];
        final category = rawCategory is Map
            ? Map<String, dynamic>.from(rawCategory)
            : null;
        final categoryName =
            category?['nome'] ?? normalized['categoria_nome'] ?? 'Outros';
        return {
          ...normalized,
          'categoria_nome': categoryName,
          'categoria_icone': _resolveCheckoutCategoryIcon(
            categoryName?.toString(),
            category?['icone'] ?? normalized['categoria_icone'],
          ),
        };
      }),
    ).where((product) => product['ativo'] != false).toList();

    final productCategories = products
        .map((product) => product['categoria_nome']?.toString())
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toSet();

    final visibleCategories = categories
        .where((category) => productCategories.contains(category['nome']))
        .toList();

    return _CheckoutAddItemsCatalog(
      categories: [
        {
          'id': 0,
          'nome': 'Todos',
          'icone': 'asset:assets/icons/todos_category.svg',
        },
        ...visibleCategories,
      ],
      products: products,
    );
  }

  Future<void> _showAddMoreItemsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _CheckoutAddItemsSheet(
          cartService: _cartService,
          loadCatalog: _loadCheckoutAddItemsCatalog,
        );
      },
    );
  }

  Widget _buildCheckoutSummaryItem(CartItem item) {
    const actionWidth = 96.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: item.imagemUrl != null && item.imagemUrl!.isNotEmpty
                  ? Image.network(
                      item.imagemUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildCheckoutItemPlaceholder(item);
                      },
                    )
                  : _buildCheckoutItemPlaceholder(item),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nome,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  CurrencyFormatter.format(item.preco),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                if (item.tamanhoSelecionado != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Tamanho: ${_formatOption(item.tamanhoSelecionado!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (item.saborSelecionado != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Sabor: ${_formatOption(item.saborSelecionado!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: actionWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Quantidade',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                _buildCheckoutQuantityControls(item),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.format(item.subtotal),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutItemPlaceholder(CartItem item) {
    return Container(
      color: Colors.orange[50],
      child: Center(
        child: CategoryIconWidget(
          icone: null,
          categoryName: item.categoriaNome,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildCheckoutQuantityControls(CartItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          _buildCheckoutQuantityButton(
            icon: Icons.remove,
            onPressed: () => unawaited(
              _cartService.updateQuantity(item.cartKey, item.quantidade - 1),
            ),
          ),
          Expanded(
            child: Text(
              item.quantidade.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          _buildCheckoutQuantityButton(
            icon: Icons.add,
            onPressed: () => unawaited(
              _cartService.updateQuantity(item.cartKey, item.quantidade + 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutQuantityButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          child: Icon(icon, size: 16, color: Colors.grey[800]),
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
                labelText: 'Telefone/WhatsApp *',
                prefixIcon: Icon(Icons.phone),
                prefixText: '+55 ',
                border: OutlineInputBorder(),
                hintText: '(21) 99086-5138',
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [_PhoneInputFormatter()],
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
                hintText: 'Rua e número',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Endereço é obrigatório';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _complementoController,
              decoration: const InputDecoration(
                labelText: 'Complemento',
                prefixIcon: Icon(Icons.apartment),
                border: OutlineInputBorder(),
                hintText: 'Casa, bloco, apto, referência...',
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _bairroController,
                    decoration: const InputDecoration(
                      labelText: 'Bairro *',
                      prefixIcon: Icon(Icons.holiday_village),
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
                  flex: 4,
                  child: TextFormField(
                    controller: _cepController,
                    decoration: const InputDecoration(
                      labelText: 'CEP *',
                      prefixIcon: Icon(Icons.pin_drop),
                      border: OutlineInputBorder(),
                      hintText: '00000-000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _CepInputFormatter(),
                    ],
                    validator: (value) {
                      final digitsOnly =
                          value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                      if (digitsOnly.isEmpty) {
                        return 'CEP obrigatório';
                      }
                      if (digitsOnly.length != 8) {
                        return 'CEP inválido';
                      }
                      return null;
                    },
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isUsingCurrentLocation
                          ? null
                          : _validateCurrentDeviceLocation,
                      icon: _isUsingCurrentLocation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isUsingCurrentLocation
                              ? 'Obtendo...'
                              : 'Usar localização',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                        side: BorderSide(color: Colors.orange[300]!),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed:
                          _isSelectingLocationOnMap || _isCheckingDeliveryArea
                          ? null
                          : _openDeliveryMapPicker,
                      icon: _isSelectingLocationOnMap
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.add_location_alt_outlined,
                              size: 20,
                            ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSelectingLocationOnMap
                              ? 'Validando...'
                              : 'Selecionar no mapa',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                        side: BorderSide(color: Colors.orange[300]!),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDeliveryAreaValidationStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    final user = Supabase.instance.client.auth.currentUser;
    final bool isGuest = user == null;
    final int pedidosMinimosDinheiro =
        _cashPaymentSettings.minimumCompletedOrders;
    final bool dinheiroLiberadoParaTodos =
        _cashPaymentSettings.enabledForAllUsers;
    final bool podeUsarDinheiro = _cashPaymentSettings.canUse(
      isGuest: isGuest,
      completedOrders: _pedidosConcluidos,
    );
    final bool isAdmin = _isAdmin;

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
                  _isPedidoTeste = false;
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PIX',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Pagamento no app',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
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
                  _isPedidoTeste = false;
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
                          Image.asset(
                            'assets/icons/menu/credit_card.png',
                            width: 24,
                            height: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cartão de Crédito',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Pagamento no app',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
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

            // Dinheiro - Requer login e 5 pedidos concluídos
            Opacity(
              opacity: podeUsarDinheiro ? 1.0 : 0.5,
              child: InkWell(
                onTap: podeUsarDinheiro
                    ? () {
                        setState(() {
                          _metodoPagamento = 'dinheiro';
                          _isPedidoTeste = false;
                        });
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isGuest
                                  ? '🔒 Visitantes não podem pagar em dinheiro. Faça login ou cadastre-se.'
                                  : dinheiroLiberadoParaTodos
                                  ? '🔒 O pagamento em dinheiro foi liberado apenas para clientes autenticados.'
                                  : '🔒 Você precisa de $pedidosMinimosDinheiro pedidos concluídos para pagar em dinheiro. Progresso: $_pedidosConcluidos/$pedidosMinimosDinheiro',
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/icons/menu/money.png',
                              width: 24,
                              height: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Dinheiro',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
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
                                  const SizedBox(height: 2),
                                  Text(
                                    podeUsarDinheiro
                                        ? 'Pagamento na entrega'
                                        : isGuest
                                        ? 'Indisponível para visitantes'
                                        : dinheiroLiberadoParaTodos
                                        ? 'Disponível para clientes autenticados'
                                        : 'Requer $_pedidosConcluidos/$pedidosMinimosDinheiro pedidos concluídos',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
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
                        'Total: ${CurrencyFormatter.format(_totalComTaxa)}',
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

            // Opção de pedido teste (somente admin)
            if (isAdmin) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    if (_isPedidoTeste) {
                      _isPedidoTeste = false;
                      _metodoPagamento = 'pix';
                    } else {
                      _isPedidoTeste = true;
                      _metodoPagamento = 'teste';
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isPedidoTeste
                          ? Colors.deepPurple
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _isPedidoTeste
                        ? Colors.deepPurple.withValues(alpha: 0.1)
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
                            color: _isPedidoTeste
                                ? Colors.deepPurple
                                : Colors.grey,
                            width: 2,
                          ),
                          color: _isPedidoTeste ? Colors.deepPurple : null,
                        ),
                        child: _isPedidoTeste
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.science, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pedido de Teste (Admin)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Sem pagamento. O pedido será marcado como teste.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Calcula a data mínima para entrega considerando D+1 e regras de fim de semana
  DateTime _calcularDataMinimaEntrega() {
    final now = DateTime.now();
    final baseDate = now.hour >= 21 ? now.add(const Duration(days: 1)) : now;
    DateTime minDate;

    switch (baseDate.weekday) {
      case DateTime.friday:
        // Sexta: próxima entrega é segunda
        minDate = baseDate.add(const Duration(days: 3));
        break;
      case DateTime.saturday:
        // Sábado: próxima entrega é segunda
        minDate = baseDate.add(const Duration(days: 2));
        break;
      case DateTime.sunday:
        // Domingo: próxima entrega é segunda
        minDate = baseDate.add(const Duration(days: 1));
        break;
      default:
        // Seg-Qui: D+1 normal, com corte às 21h.
        minDate = baseDate.add(const Duration(days: 1));
        // Se D+1 cair no domingo, pular para segunda
        if (minDate.weekday == DateTime.sunday) {
          minDate = minDate.add(const Duration(days: 1));
        }
    }

    return DateTime(minDate.year, minDate.month, minDate.day);
  }

  DateTime _proximaDataEntregaValida(DateTime date) {
    var result = DateTime(date.year, date.month, date.day);
    while (!_isDataEntregaValida(result)) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }

  // Verifica se uma data é válida para entrega (sem entregas no fim de semana)
  bool _isDataEntregaValida(DateTime date) {
    return date.weekday != DateTime.saturday && date.weekday != DateTime.sunday;
  }

  String _formatDate(DateTime date) {
    const diasSemana = [
      '',
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    return '${diasSemana[date.weekday]}, $dia/$mes/${date.year}';
  }

  String _deliveryPolicyLabel() {
    return DateTime.now().hour >= 21 ? 'D+2' : 'D+1';
  }

  Widget _buildScheduleSection() {
    final dataMinima = _calcularDataMinimaEntrega();
    final policyLabel = _deliveryPolicyLabel();

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
                Icon(Icons.calendar_today, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Entrega',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dataEntrega == null
                              ? 'Entrega padrão: ${_formatDate(dataMinima)} ($policyLabel)'
                              : 'Sem agendamento: entrega em ${_formatDate(dataMinima)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deseja receber em outra data? Agende abaixo para escolher o dia de sua preferência.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      var initialDate = _proximaDataEntregaValida(
                        _dataEntrega ?? dataMinima,
                      );
                      if (initialDate.isBefore(dataMinima)) {
                        initialDate = _proximaDataEntregaValida(dataMinima);
                      }
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: dataMinima,
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                        selectableDayPredicate: _isDataEntregaValida,
                        helpText: 'Escolha a data de entrega',
                        cancelText: 'Cancelar',
                        confirmText: 'Confirmar',
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.orange[700]!,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _dataEntrega = picked);
                      }
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _dataEntrega != null
                          ? _formatDate(_dataEntrega!)
                          : 'Escolher data',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange[700],
                      side: BorderSide(color: Colors.orange[300]!),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (_dataEntrega != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => _dataEntrega = null),
                    icon: const Icon(Icons.close, color: Colors.red),
                    tooltip: 'Remover agendamento (usar D+1)',
                  ),
                ],
              ],
            ),

            if (_dataEntrega != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Entrega agendada para ${_formatDate(_dataEntrega!)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
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
                Flexible(
                  child: Text(
                    '${CurrencyFormatter.format(_totalComTaxa)} / $_cartItemCountLabel',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
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

    final cepDigits = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepDigits.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Por favor, informe um CEP válido')),
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
        _troco < _totalComTaxa) {
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

    final atendeAreaEntrega = await _validateDeliveryArea(
      showDialogOnFailure: true,
    );
    if (!atendeAreaEntrega) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Obter usuário atual
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }

      final totalPedido = _totalComTaxa;
      final metodoPagamentoPedido = _isPedidoTeste ? 'teste' : _metodoPagamento;
      final isOnlinePayment =
          !_isPedidoTeste &&
          OrderPaymentService.requiresOnlinePayment(_metodoPagamento);

      final pedido = await OrderPaymentService.createOrderWithItems(
        pedidoData: _buildPedidoData(
          user: user,
          metodoPagamentoPedido: metodoPagamentoPedido,
          isOnlinePayment: isOnlinePayment,
        ),
        itens: _buildPedidoItensPayload(),
      );

      try {
        await _saveUserAddress();
      } catch (e) {
        debugPrint('Erro ao salvar endereço: $e');
      }

      if (isOnlinePayment) {
        await _cartService.clearCart();
        if (!mounted) return;

        final paymentResult = await _openPendingPaymentFlow(
          pedido: pedido,
          user: user,
        );

        if (paymentResult?['success'] == true) {
          final pedidoAtualizado =
              await OrderPaymentService.fetchOrderById(pedido['id']) ?? pedido;
          if (!mounted) return;
          _showSuccessDialog(pedidoAtualizado, totalPedido);
        } else {
          final pedidoAtualizado =
              await OrderPaymentService.fetchOrderById(pedido['id']) ?? pedido;
          if (!mounted) return;
          _showPendingPaymentDialog(pedidoAtualizado, totalPedido);
        }
        return;
      }

      try {
        final orderId = pedido['id'];
        if (orderId is int) {
          await NotificationService.notifyAdminsNewOrder(
            orderId: orderId,
            customerName: _nomeController.text.trim(),
            total: totalPedido,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao notificar admins: $e');
      }

      await _cartService.clearCart();
      if (!mounted) return;

      _showSuccessDialog(pedido, totalPedido);
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

  Map<String, dynamic> _buildPedidoData({
    required User user,
    required String metodoPagamentoPedido,
    required bool isOnlinePayment,
  }) {
    return {
      'user_id': user.id,
      'cliente_nome': _nomeController.text.trim(),
      'cliente_telefone': _telefoneController.text.trim(),
      'endereco_completo': _enderecoController.text.trim(),
      'complemento': _complementoController.text.trim().isEmpty
          ? null
          : _complementoController.text.trim(),
      'bairro': _bairroController.text.trim(),
      'cidade': _cidadeController.text.trim(),
      'cep': _cepController.text.trim().isEmpty
          ? null
          : _cepController.text.trim(),
      'metodo_pagamento': metodoPagamentoPedido,
      'valor_troco': _metodoPagamento == 'dinheiro' && _troco > 0
          ? _troco
          : null,
      'total': _totalComTaxa,
      'status': _isPedidoTeste
          ? 'teste'
          : isOnlinePayment
          ? OrderPaymentService.statusPagamentoPendente
          : OrderPaymentService.statusPendente,
      'payment_status': isOnlinePayment
          ? OrderPaymentService.paymentStatusPending
          : null,
      'payment_provider': isOnlinePayment
          ? _paymentProviderForMethod(_metodoPagamento)
          : null,
      'payment_reference': null,
      'payment_url': null,
      'payment_payload': <String, dynamic>{},
      'payment_expires_at': null,
      'payment_confirmed_at': null,
      'is_teste': _isPedidoTeste,
      'observacoes': _observacoesController.text.trim().isEmpty
          ? null
          : _observacoesController.text.trim(),
      'data_entrega':
          _dataEntrega?.toIso8601String() ??
          _calcularDataMinimaEntrega().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _buildPedidoItensPayload() {
    return _cartService.items.map((item) {
      return {
        'produto_id': int.parse(item.id),
        'quantidade': item.quantidade,
        'preco_unitario': item.preco,
        'subtotal': item.subtotal,
        'observacoes': item.observacoes,
        'tamanho_selecionado': item.tamanhoSelecionado,
        if (item.saborSelecionado != null)
          'sabor_selecionado': item.saborSelecionado,
        if (item.saborSelecionado != null && item.imagemUrl != null)
          'imagem_url': item.imagemUrl,
      };
    }).toList();
  }

  String _paymentProviderForMethod(String metodo) {
    switch (metodo) {
      case 'pix':
        return OrderPaymentService.providerPix;
      case 'credito':
        return OrderPaymentService.providerCard;
      default:
        return '';
    }
  }

  Future<Map<String, dynamic>?> _openPendingPaymentFlow({
    required Map<String, dynamic> pedido,
    required User user,
  }) async {
    // Usar total do pedido já salvo no DB (o carrinho pode já estar limpo)
    final amount = (pedido['total'] as num).toDouble();

    if (_metodoPagamento == 'pix') {
      return Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => AbacatePayPaymentScreen(
            pedidoId: pedido['id'].toString(),
            amount: amount,
            description: 'Pedido #${pedido['id']} - Carro das Delícias',
            initialChargeId: pedido['payment_reference']?.toString(),
            initialPaymentPayload: OrderPaymentService.parsePaymentPayload(
              pedido['payment_payload'],
            ),
            initialExpiresAt: pedido['payment_expires_at']?.toString(),
          ),
        ),
      );
    }

    if (_metodoPagamento == 'credito') {
      return Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => StripePaymentScreen(
            pedidoId: pedido['id'].toString(),
            amount: amount,
            description: 'Pedido #${pedido['id']} - Carro das Delícias',
            customerEmail: user.email ?? '',
            initialSessionId: pedido['payment_reference']?.toString(),
            initialCheckoutUrl: pedido['payment_url']?.toString(),
            initialPaymentPayload: OrderPaymentService.parsePaymentPayload(
              pedido['payment_payload'],
            ),
          ),
        ),
      );
    }

    return null;
  }

  void _showPendingPaymentDialog(
    Map<String, dynamic> pedido,
    double totalPedido,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.pending_actions, color: Colors.orange[700], size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Pagamento Pendente')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seu pedido #${pedido['id'].toString().padLeft(4, '0')} foi salvo com o pagamento pendente.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.attach_money, color: Colors.green[700], size: 20),
                  const SizedBox(width: 4),
                  Text('Total: ${CurrencyFormatter.format(totalPedido)}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _getPaymentMethodIcon(_metodoPagamento),
                  const SizedBox(width: 4),
                  Text('Pagamento: ${_getPaymentMethodName(_metodoPagamento)}'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Você pode retomar esse pagamento a qualquer momento em "Meus Pedidos".',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.schedule),
                label: const Text('Depois'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    MainNavigationService.navigateToOrders();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Ver Pedidos'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(Map<String, dynamic> pedido, double totalPedido) {
    final dataEntregaStr = pedido['data_entrega'] != null
        ? _formatDate(DateTime.parse(pedido['data_entrega']))
        : _formatDate(_calcularDataMinimaEntrega());

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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seu pedido #${pedido['id'].toString().padLeft(4, '0')} foi registrado com sucesso!',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.attach_money, color: Colors.green[700], size: 20),
                  const SizedBox(width: 4),
                  Text('Total: ${CurrencyFormatter.format(totalPedido)}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _getPaymentMethodIcon(_metodoPagamento),
                  const SizedBox(width: 4),
                  Text('Pagamento: ${_getPaymentMethodName(_metodoPagamento)}'),
                ],
              ),
              const SizedBox(height: 4),
              Text('📅 Entrega: $dataEntregaStr'),
              const SizedBox(height: 12),
              const Text(
                'Se necessário, entraremos em contato para confirmar os detalhes da entrega.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ Importante: Caso os dados de contato ou endereço informados estejam incorretos e não seja possível localizar o cliente, não haverá devolução do valor pago.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              // Fechar diálogo
              Navigator.of(context).pop();

              // Voltar para a tela principal (MainScreen)
              // Usar popUntil para remover todas as rotas até a primeira
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.check_circle, color: Colors.white),
            label: const Text('OK'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
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

  Widget _getPaymentMethodIcon(String method, {double size = 20}) {
    switch (method) {
      case 'pix':
        return Image.network(
          'https://img.icons8.com/color/48/pix.png',
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.payment, size: size, color: Colors.purple[700]),
        );
      case 'credito':
      case 'debito':
        return Image.asset(
          'assets/icons/menu/credit_card.png',
          width: size,
          height: size,
        );
      case 'dinheiro':
        return Image.asset(
          'assets/icons/menu/money.png',
          width: size,
          height: size,
        );
      default:
        return Icon(Icons.payment, size: size, color: Colors.purple[700]);
    }
  }

  String _formatOption(String optionJson) {
    try {
      final option = json.decode(optionJson);
      if (option is Map<String, dynamic>) {
        return option['nome'] ?? option['name'] ?? optionJson;
      }
      return optionJson;
    } catch (e) {
      return optionJson;
    }
  }
}

class _CheckoutAddItemsCatalog {
  const _CheckoutAddItemsCatalog({
    required this.categories,
    required this.products,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> products;
}

class _CheckoutAddItemsSheet extends StatefulWidget {
  const _CheckoutAddItemsSheet({
    required this.cartService,
    required this.loadCatalog,
  });

  final CartService cartService;
  final Future<_CheckoutAddItemsCatalog> Function() loadCatalog;

  @override
  State<_CheckoutAddItemsSheet> createState() => _CheckoutAddItemsSheetState();
}

class _CheckoutAddItemsSheetState extends State<_CheckoutAddItemsSheet> {
  late Future<_CheckoutAddItemsCatalog> _catalogFuture;
  String _selectedCategory = 'Todos';
  final Set<String> _addingProductIds = {};
  final Map<String, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    _catalogFuture = widget.loadCatalog();
  }

  void _reloadCatalog() {
    setState(() {
      _selectedCategory = 'Todos';
      _catalogFuture = widget.loadCatalog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.86;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_shopping_cart,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Adicionar itens',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<_CheckoutAddItemsCatalog>(
                future: _catalogFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState(snapshot.error);
                  }

                  final catalog = snapshot.data;
                  if (catalog == null || catalog.products.isEmpty) {
                    return _buildEmptyState();
                  }

                  final products = _filteredProducts(catalog.products);

                  return Column(
                    children: [
                      _buildCategoryFilters(catalog.categories),
                      const SizedBox(height: 12),
                      Expanded(
                        child: products.isEmpty
                            ? _buildEmptyCategoryState()
                            : ListView.separated(
                                itemCount: products.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  return _buildProductTile(products[index]);
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredProducts(
    List<Map<String, dynamic>> products,
  ) {
    if (_selectedCategory == 'Todos') return products;
    return products
        .where((product) => product['categoria_nome'] == _selectedCategory)
        .toList();
  }

  Widget _buildCategoryFilters(List<Map<String, dynamic>> categories) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final categoryName = category['nome']?.toString() ?? 'Categoria';
          final selected = categoryName == _selectedCategory;

          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            onSelected: (_) {
              setState(() => _selectedCategory = categoryName);
            },
            avatar: SizedBox(
              width: 18,
              height: 18,
              child: CategoryIconWidget(
                icone: category['icone'],
                categoryName: categoryName,
                size: 18,
              ),
            ),
            label: Text(categoryName),
            selectedColor: Colors.green[100],
            backgroundColor: Colors.grey[100],
            side: BorderSide(
              color: selected ? Colors.green[300]! : Colors.grey[300]!,
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.green[800] : Colors.black87,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product) {
    final productId = product['id']?.toString() ?? product.hashCode.toString();
    final images = ProductVariantUtils.productImages(product);
    final isAdding = _addingProductIds.contains(productId);
    final isAvailable = product['ativo'] != false;
    final categoryName = product['categoria_nome']?.toString() ?? '';
    final quantity = _quantityFor(productId);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 58,
              height: 58,
              child: images.isNotEmpty
                  ? Image.network(
                      images.first,
                      fit: BoxFit.cover,
                      cacheWidth: 180,
                      cacheHeight: 180,
                      errorBuilder: (_, _, _) =>
                          _buildProductPlaceholder(product),
                    )
                  : _buildProductPlaceholder(product),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product['nome']?.toString() ?? 'Produto',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (categoryName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _buildProductCategoryChip(product),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                _buildProductPrice(product),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModalQuantityControls(productId, quantity),
                const SizedBox(height: 7),
                SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: isAvailable && !isAdding
                        ? () => _addProduct(product)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isAdding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_shopping_cart, size: 19),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductPlaceholder(Map<String, dynamic> product) {
    return Container(
      color: Colors.green[50],
      child: Center(
        child: CategoryIconWidget(
          icone: product['categoria_icone'],
          categoryName: product['categoria_nome']?.toString(),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildProductCategoryChip(Map<String, dynamic> product) {
    final categoryName = product['categoria_nome']?.toString() ?? '';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 74),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CategoryIconWidget(
                icone: product['categoria_icone'],
                categoryName: categoryName,
                size: 13,
              ),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _quantityFor(String productId) {
    return _quantities[productId] ?? 1;
  }

  void _setQuantity(String productId, int quantity) {
    setState(() {
      _quantities[productId] = quantity.clamp(1, 99).toInt();
    });
  }

  Widget _buildModalQuantityControls(String productId, int quantity) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          _buildModalQuantityButton(
            icon: Icons.remove,
            onPressed: quantity > 1
                ? () => _setQuantity(productId, quantity - 1)
                : null,
          ),
          Expanded(
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          _buildModalQuantityButton(
            icon: Icons.add,
            onPressed: () => _setQuantity(productId, quantity + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildModalQuantityButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Icon(
            icon,
            size: 15,
            color: onPressed == null ? Colors.grey[400] : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _buildProductPrice(Map<String, dynamic> product) {
    final priceInfo = _getProductDisplayPriceInfo(product);
    final currentPrice = priceInfo['currentPrice'] as double?;
    final previousPrice = priceInfo['previousPrice'] as double?;
    final hasDiscount = priceInfo['hasDiscount'] as bool;
    final hasMultiplePrices = priceInfo['hasMultiplePrices'] as bool;
    final discountPercentage = priceInfo['discountPercentage'] as int?;

    if (currentPrice == null) {
      return Text(
        'Sem preço',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDiscount && previousPrice != null) ...[
          Text(
            CurrencyFormatter.format(previousPrice),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              decoration: TextDecoration.lineThrough,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${hasMultiplePrices ? 'A partir de ' : ''}${CurrencyFormatter.format(currentPrice)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: hasDiscount ? Colors.orange : Colors.green[700],
                height: 1.05,
              ),
            ),
            if (discountPercentage != null)
              _buildDiscountChip(discountPercentage),
          ],
        ),
      ],
    );
  }

  Map<String, dynamic> _getProductDisplayPriceInfo(
    Map<String, dynamic> product,
  ) {
    final sizes = ProductVariantUtils.extractSizes(product['tamanhos']);
    final previousPrice = ProductVariantUtils.toDouble(
      product['preco_anterior'],
    );

    if (sizes.isNotEmpty) {
      final prices = sizes
          .map((size) => ProductVariantUtils.toDouble(size['preco']))
          .whereType<double>()
          .where((price) => price > 0)
          .toSet()
          .toList();

      if (prices.isEmpty) {
        return {
          'currentPrice': null,
          'previousPrice': null,
          'hasDiscount': false,
          'hasMultiplePrices': false,
          'discountPercentage': null,
        };
      }

      prices.sort();
      final currentPrice = prices.first;
      final hasDiscount = previousPrice != null && previousPrice > currentPrice;

      return {
        'currentPrice': currentPrice,
        'previousPrice': hasDiscount ? previousPrice : null,
        'hasDiscount': hasDiscount,
        'hasMultiplePrices': sizes.length > 1 || prices.length > 1,
        'discountPercentage': hasDiscount
            ? (((previousPrice - currentPrice) / previousPrice) * 100).round()
            : null,
      };
    }

    final currentPrice = ProductVariantUtils.toDouble(product['preco']);
    final hasDiscount =
        previousPrice != null &&
        currentPrice != null &&
        previousPrice > currentPrice;

    return {
      'currentPrice': currentPrice,
      'previousPrice': hasDiscount ? previousPrice : null,
      'hasDiscount': hasDiscount,
      'hasMultiplePrices': false,
      'discountPercentage': hasDiscount
          ? (((previousPrice - currentPrice) / previousPrice) * 100).round()
          : null,
    };
  }

  Widget _buildDiscountChip(int discountPercentage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$discountPercentage% OFF',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _addProduct(Map<String, dynamic> product) async {
    final productId = product['id']?.toString() ?? product.hashCode.toString();
    if (_addingProductIds.contains(productId)) return;
    final quantity = _quantityFor(productId);

    setState(() => _addingProductIds.add(productId));
    try {
      await ProductActionHelper.addToCart(
        context: context,
        cartService: widget.cartService,
        produto: product,
        quantidade: quantity,
        useOverlaySnackBar: true,
        onViewCart: () {
          if (mounted) {
            Navigator.of(context).maybePop();
          }
        },
        avoidAdminFab: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao adicionar produto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _addingProductIds.remove(productId));
      }
    }
  }

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 42, color: Colors.grey[500]),
          const SizedBox(height: 10),
          const Text(
            'Não foi possível carregar os produtos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            error?.toString() ?? 'Tente novamente.',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _reloadCatalog,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 42, color: Colors.grey[500]),
          const SizedBox(height: 10),
          const Text(
            'Nenhum produto disponível',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoryState() {
    return Center(
      child: Text(
        'Nenhum produto nessa categoria',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      ),
    );
  }
}

class _DeliveryMapSelection {
  const _DeliveryMapSelection({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class _DeliveryLocationPickerPage extends StatefulWidget {
  const _DeliveryLocationPickerPage({
    required this.initialLatitude,
    required this.initialLongitude,
  });

  final double initialLatitude;
  final double initialLongitude;

  @override
  State<_DeliveryLocationPickerPage> createState() =>
      _DeliveryLocationPickerPageState();
}

class _DeliveryLocationPickerPageState
    extends State<_DeliveryLocationPickerPage> {
  late double _selectedLatitude;
  late double _selectedLongitude;
  String? _mapError;

  @override
  void initState() {
    super.initState();
    _selectedLatitude = widget.initialLatitude;
    _selectedLongitude = widget.initialLongitude;

    final mapboxToken = SupabaseConfig.mapboxAccessToken.trim();
    if (mapboxToken.isNotEmpty) {
      mapbox.MapboxOptions.setAccessToken(mapboxToken);
    }
  }

  void _onCameraChanged(mapbox.CameraChangedEventData data) {
    final coordinates = data.cameraState.center.coordinates;
    _selectedLatitude = coordinates.lat.toDouble();
    _selectedLongitude = coordinates.lng.toDouble();
  }

  void _confirmSelection() {
    Navigator.of(context).pop(
      _DeliveryMapSelection(
        latitude: _selectedLatitude,
        longitude: _selectedLongitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = mapbox.Point(
      coordinates: mapbox.Position(
        widget.initialLongitude,
        widget.initialLatitude,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Selecionar no mapa'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _confirmSelection,
            child: const Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: mapbox.MapWidget(
              key: const ValueKey('delivery-location-picker-map'),
              viewport: mapbox.CameraViewportState(
                center: initialCenter,
                zoom: 16,
              ),
              onCameraChangeListener: _onCameraChanged,
              onMapLoadErrorListener: (data) {
                if (!mounted) return;
                setState(() {
                  _mapError =
                      'Não foi possível carregar o mapa. Confira sua conexão e o token do Mapbox.';
                });
              },
            ),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -22),
              child: Icon(
                Icons.location_pin,
                size: 54,
                color: Colors.red[700],
                shadows: const [
                  Shadow(
                    blurRadius: 8,
                    color: Colors.black45,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_location_alt, color: Colors.orange[700]),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Posicione o pin no endereço de entrega.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_mapError != null)
            Positioned(
              left: 16,
              right: 16,
              top: 86,
              child: Material(
                color: Colors.red[50],
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _mapError!,
                          style: TextStyle(
                            color: Colors.red[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: ElevatedButton.icon(
                onPressed: _confirmSelection,
                icon: const Icon(Icons.check_circle),
                label: const Text('Confirmar localização'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Formatadores de entrada
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final digits = text.replaceAll(RegExp(r'[^\d]'), '');

    // Cap at 11 digits (DDD + celular)
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;

    final formatted = format(capped);

    // Calculate cursor position based on digit count before cursor
    int cursorPos = newValue.selection.baseOffset.clamp(0, text.length);
    int digitsBeforeCursor = text
        .substring(0, cursorPos)
        .replaceAll(RegExp(r'[^\d]'), '')
        .length;

    // If digits were capped, adjust digitsBeforeCursor
    if (digitsBeforeCursor > capped.length) {
      digitsBeforeCursor = capped.length;
    }

    int newPos = _mapDigitCountToOffset(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: newPos.clamp(0, formatted.length),
      ),
    );
  }

  static String format(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return '($digits';
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
  }

  int _mapDigitCountToOffset(String formatted, int digitCount) {
    int count = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        if (count == digitCount) return i;
        count++;
      }
    }
    return formatted.length;
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
