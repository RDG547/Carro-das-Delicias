import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../widgets/base_screen.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';
import '../services/image_service.dart';
import '../services/favorites_service.dart';
import '../widgets/animated_widgets.dart';

class ProfileScreen extends StatefulWidget {
  final bool isGuestMode;

  const ProfileScreen({super.key, this.isGuestMode = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _cepController = TextEditingController();

  // Máscara para CEP
  String _formatCEP(String value) {
    // Remove todos os caracteres não numéricos
    value = value.replaceAll(RegExp(r'[^0-9]'), '');

    // Limita a 8 dígitos
    if (value.length > 8) {
      value = value.substring(0, 8);
    }

    // Aplica a formatação: 00000-000
    if (value.length >= 5) {
      value = '${value.substring(0, 5)}-${value.substring(5)}';
    }

    return value;
  }

  bool _isLoading = false;
  bool _isEditing = false;
  Map<String, dynamic>? _userProfile;
  bool _isAdmin = false;

  // Campos para upload de foto
  File? _selectedImage;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;

  // Estatísticas do usuário
  int _totalPedidos = 0;
  int _totalFavoritos = 0;

  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    if (!widget.isGuestMode) {
      _loadUserProfile();
      _loadUserStats();
      // Atrasa a verificação para depois do primeiro build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAdminStatus();
      });
    }
    _fadeController.forward();
  }

  Future<void> _checkAdminStatus() async {
    if (_isAdmin) return; // Já verificado, evita verificações desnecessárias

    try {
      final user = Supabase.instance.client.auth.currentUser;
      debugPrint('🔍 Profile - Verificando admin status - user: ${user?.id}');

      if (user == null) {
        debugPrint('⚠️ Profile - Usuário não autenticado');
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('📊 Profile - Resposta da query: $response');

      if (mounted && response != null) {
        final isAdmin = response['role'] == 'admin';
        debugPrint('✅ Profile - is_admin definido como: $isAdmin');
        if (_isAdmin != isAdmin) {
          setState(() => _isAdmin = isAdmin);
        }
      } else {
        debugPrint('⚠️ Profile - Response null ou widget desmontado');
      }
    } catch (e) {
      debugPrint('❌ Profile - Erro ao verificar status admin: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _cepController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Carregar dados do perfil do usuário
        final response = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            _userProfile = response;
            _nameController.text = response['name'] ?? '';
            _phoneController.text = response['phone'] ?? '';
            _addressController.text = response['address'] ?? '';
            _neighborhoodController.text = response['neighborhood'] ?? '';
            _cityController.text = response['city'] ?? '';
            // Formatar CEP ao carregar do banco
            final cepValue = response['cep'] ?? '';
            _cepController.text = cepValue.isNotEmpty
                ? _formatCEP(cepValue)
                : '';
            _uploadedImageUrl = response['avatar_url'];
          });
        } else {
          // Se não existe perfil, usar dados do auth
          setState(() {
            _userProfile = {
              'id': user.id,
              'email': user.email,
              'name': user.userMetadata?['name'] ?? '',
              'phone': user.userMetadata?['phone'] ?? '',
            };
            _nameController.text = user.userMetadata?['name'] ?? '';
            _phoneController.text = user.userMetadata?['phone'] ?? '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar perfil: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserStats() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Carregar total de pedidos do usuário
        final pedidosResponse = await Supabase.instance.client
            .from('pedidos')
            .select('id')
            .eq('user_id', user.id);

        // Carregar total de favoritos do serviço
        final favoritesService = FavoritesService();
        await favoritesService.loadFavorites();
        final totalFavoritos = favoritesService.totalFavorites;

        if (mounted) {
          setState(() {
            _totalPedidos = pedidosResponse.length;
            _totalFavoritos = totalFavoritos;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar estatísticas: $e');
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nome é obrigatório')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Dados básicos que sempre existem
        final profileData = {
          'id': user.id,
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': user.email,
          'updated_at': DateTime.now().toIso8601String(),
        };

        // Adicionar avatar_url se foi feito upload
        if (_uploadedImageUrl != null) {
          profileData['avatar_url'] = _uploadedImageUrl;
        }

        // Tentar adicionar campos de endereço (podem não existir na tabela ainda)
        try {
          final profileDataWithAddress = {
            ...profileData,
            'address': _addressController.text.trim(),
            'neighborhood': _neighborhoodController.text.trim(),
            'city': _cityController.text.trim(),
            'cep': _cepController.text.replaceAll(RegExp(r'[^0-9]'), ''),
          };

          await Supabase.instance.client
              .from('profiles')
              .upsert(profileDataWithAddress);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Perfil atualizado com sucesso!'),
                backgroundColor: Colors.green,
              ),
            );

            setState(() {
              _isEditing = false;
              _userProfile = profileDataWithAddress;
            });
          }
        } catch (addressError) {
          // Se falhar com endereço, tenta salvar sem os campos de endereço
          debugPrint(
            'Erro ao salvar endereço (colunas podem não existir): $addressError',
          );

          await Supabase.instance.client.from('profiles').upsert(profileData);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Perfil atualizado (endereço não pode ser salvo - contate o administrador)',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );

            setState(() {
              _isEditing = false;
              _userProfile = profileData;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar perfil: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _goToHome() {
    debugPrint('🔙 Botão de voltar pressionado na tela de perfil');

    // Verifica se estamos em uma rota que pode fazer pop
    if (Navigator.of(context).canPop()) {
      // Verifica quantas rotas existem e remove todas menos a primeira
      int popCount = 0;
      Navigator.of(context).popUntil((route) {
        popCount++;
        return route.isFirst || popCount > 10; // Limite de segurança
      });
    } else {
      // Estamos no PageView (navegação pela navbar), navega para a home
      debugPrint('🏠 Navegando para home via MainNavigationProvider');
      final provider = MainNavigationProvider.of(context);
      if (provider?.navigateToPage != null) {
        provider!.navigateToPage!(0); // Índice 0 = Início
      }
    }
  }

  Future<void> _selectProfileImage() async {
    final image = await ImageService.showImagePickerDialog(context);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Fazer upload da nova imagem (já deleta a anterior automaticamente)
      final imageUrl = await ImageService.uploadProfileImage(
        imageFile: _selectedImage!,
        userId: user.id,
        oldImageUrl: _uploadedImageUrl,
      );

      if (imageUrl != null) {
        // Atualizar no banco de dados
        await Supabase.instance.client
            .from('profiles')
            .update({'avatar_url': imageUrl})
            .eq('id', user.id);

        setState(() {
          _uploadedImageUrl = imageUrl;
          _selectedImage = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto de perfil atualizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao enviar foto'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  void _removeProfileImage() {
    setState(() {
      _selectedImage = null;
      _uploadedImageUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return BaseScreen(
      onBackPressed: _goToHome,
      title: 'Perfil',
      showBackButton: true, // Garantir que o botão de voltar seja mostrado
      actions: [AppMenu(isGuestMode: widget.isGuestMode, isAdmin: _isAdmin)],
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : widget.isGuestMode
            ? _buildGuestView()
            : _buildUserProfile(user),
      ),
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.visibility_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 24),
          const Text(
            'Modo Visitante',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Faça login para acessar seu perfil\ne personalizar sua experiência.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          AnimatedButton(
            text: 'Fazer Login',
            onPressed: () {
              Navigator.of(context).pop();
              // Aqui você pode navegar para a tela de login se necessário
            },
            backgroundColor: Colors.black,
            textColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfile(User? user) {
    return Column(
      children: [
        // Avatar e informações básicas
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.black, Colors.grey],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Avatar com upload de foto
              Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    backgroundImage: _selectedImage != null
                        ? FileImage(_selectedImage!)
                        : _uploadedImageUrl != null
                        ? NetworkImage(_uploadedImageUrl!)
                        : null,
                    child: _selectedImage == null && _uploadedImageUrl == null
                        ? Text(
                            (_userProfile?['name']?.substring(0, 1) ??
                                    user?.userMetadata?['name']?.substring(
                                      0,
                                      1,
                                    ) ??
                                    user?.email?.substring(0, 1) ??
                                    'U')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: IconButton(
                        onPressed: _isUploadingImage
                            ? null
                            : _selectProfileImage,
                        icon: _isUploadingImage
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),

              // Botões de ação para upload de foto
              if (_selectedImage != null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isUploadingImage ? null : _uploadProfileImage,
                      icon: _isUploadingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(
                        _isUploadingImage ? 'Enviando...' : 'Confirmar',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isUploadingImage ? null : _removeProfileImage,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancelar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              Text(
                _userProfile?['name'] ??
                    user?.userMetadata?['name'] ??
                    'Usuário',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                user?.email ?? '',
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ],
          ),
        ),

        // TabBar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.black,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(
                child: SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Informações Pessoais',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              Tab(
                child: SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text('Estatísticas', textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
        ),

        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildPersonalInfoTab(user), _buildStatisticsTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Suas Estatísticas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Pedidos',
                      _totalPedidos.toString(),
                      Icons.shopping_cart,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Favoritos',
                      _totalFavoritos.toString(),
                      Icons.favorite,
                      Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoTab(User? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Informações Pessoais',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(_isEditing ? Icons.close : Icons.edit),
                    onPressed: () {
                      setState(() {
                        _isEditing = !_isEditing;
                        if (!_isEditing) {
                          // Restaurar valores originais ao cancelar
                          _nameController.text = _userProfile?['name'] ?? '';
                          _phoneController.text = _userProfile?['phone'] ?? '';
                          _addressController.text =
                              _userProfile?['address'] ?? '';
                          _neighborhoodController.text =
                              _userProfile?['neighborhood'] ?? '';
                          _cityController.text = _userProfile?['city'] ?? '';
                          // Formatar CEP ao restaurar valores
                          final cepValue = _userProfile?['cep'] ?? '';
                          _cepController.text = cepValue.isNotEmpty
                              ? _formatCEP(cepValue)
                              : '';
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _nameController,
                  labelText: 'Nome Completo',
                  prefixIcon: Icons.person,
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _phoneController,
                  labelText: 'Telefone',
                  prefixIcon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(height: 16),

              // Campos de endereço
              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _addressController,
                  labelText: 'Endereço Completo',
                  prefixIcon: Icons.home,
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _neighborhoodController,
                  labelText: 'Bairro',
                  prefixIcon: Icons.location_city,
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _cityController,
                  labelText: 'Cidade',
                  prefixIcon: Icons.location_city,
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: !_isEditing,
                child: AnimatedTextField(
                  controller: _cepController,
                  labelText: 'CEP',
                  prefixIcon: Icons.pin_drop,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(9), // 8 dígitos + 1 hífen
                    _CEPInputFormatter(),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: true,
                child: AnimatedTextField(
                  controller: TextEditingController(text: user?.email ?? ''),
                  labelText: 'Email',
                  prefixIcon: Icons.email,
                ),
              ),

              if (_isEditing) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: AnimatedButton(
                    text: 'Salvar Alterações',
                    onPressed: _updateProfile,
                    backgroundColor: Colors.green,
                    textColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 14, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

/// Formatter para CEP que aplica a máscara 00000-000
class _CEPInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove todos os caracteres não numéricos
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limita a 8 dígitos
    if (text.length > 8) {
      text = text.substring(0, 8);
    }

    // Aplica a formatação: 00000-000
    if (text.length >= 5) {
      text = '${text.substring(0, 5)}-${text.substring(5)}';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
