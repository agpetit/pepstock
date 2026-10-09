import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/product.dart';
import 'models/order_record.dart';
import 'services/database_helper.dart';
import 'services/api_service.dart';
import 'services/dolibarr_service.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();

  DatabaseHelper.ensureInitialized();

  runApp(const pepStock());
}

class pepStock extends StatelessWidget {
  const pepStock({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pepStock - Pépinière de l\'Île',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E40AF),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
          ),
        ),
      ),
      home: const ProductOrderScreen(),
    );
  }
}

class ProductOrderScreen extends StatefulWidget {
  const ProductOrderScreen({super.key});

  @override
  State<ProductOrderScreen> createState() => _ProductOrderScreenState();
}

class _ProductOrderScreenState extends State<ProductOrderScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();

  Product? _selectedProduct;
  List<ProductOption> _currentOptions = [];
  bool _isSyncing = false;
  String? _syncStatusMessage;
  bool _syncSuccess = false;

  final List<OrderItem> _accumulatedItems = [];

  String _catalogSource = 'Initialisation...';
  bool _isFallbackMode = false;
  bool _isLoadingCatalog = false;

  final dbHelper = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _initCatalogWithFallback();
  }

  Future<void> _initCatalogWithFallback() async {
    setState(() => _isLoadingCatalog = true);
    try {
      // 1. On tente de s'authentifier d'abord pour générer/récupérer la clé API
      // Remplacez par vos vrais identifiants ou passez reset: true si besoin
      /*bool isLogged = await DolibarrService.instance.login('apetit', '4Remparts!1205', reset: true);
      print(isLogged);
      if (!isLogged) {
        throw Exception("Échec de l'authentification (identifiants incorrects ou serveur injoignable).");
      }*/

      // 2. Si le login réussit, on télécharge le catalogue avec la clé validée
      final products = await DolibarrService.instance.fetchAndSyncProductsToSqlite();

      setState(() {
        _catalogSource = 'ERP (direct)';
        _isFallbackMode = false;
        _syncStatusMessage = '${products.length} produits synchronisés depuis l\'ERP.';
      });
    } catch (err) {
      // BASCULE DE SECOURS AUTOMATIQUE VERS LE FICHIER LOCAL JSON
      print('Échec communication ERP ($err) -> Chargement local');
      final localProducts = await dbHelper.restoreFromLocalAsset();
      setState(() {
        _catalogSource = 'Fichier JSON local (Mode Secours)';
        _isFallbackMode = true;
        _syncStatusMessage = 'ERP injoignable : catalogue restauré localement (${localProducts.length} produits).';
      });
    } finally {
      setState(() => _isLoadingCatalog = false);
    }
  }

  /// Recharge manuelle du fichier local JSON
  Future<void> _loadLocalJsonFallback() async {
    final localProducts = await dbHelper.restoreFromLocalAsset();
    setState(() {
      _catalogSource = 'Fichier JSON local';
      _isFallbackMode = true;
      _syncStatusMessage = '${localProducts.length} produits chargés depuis le fichier local JSON.';
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _notesController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  void _onProductSelected(Product product) {
    setState(() {
      _selectedProduct = product;
      _codeController.text = product.code;
      // Duplication des options pour gestion de sélection dynamique
      _currentOptions = product.options.map((opt) => opt.copyWith()).toList();
      _syncStatusMessage = null;
    });
  }

  // Prix unitaire de la sélection en cours (produit + options cochées)
  double get _currentUnitPrice {
    if (_selectedProduct == null) return 0.0;
    double total = _selectedProduct!.basePrice;
    for (var opt in _currentOptions) {
      if (opt.isSelected) {
        total += opt.price;
      }
    }
    return total;
  }

  // Sous-total de la sélection en cours
  double get _currentLineTotal => _currentUnitPrice * _quantity;

  // Montant total cumulé de l'ensemble des articles du panier
  double get _grandTotalPrice {
    return _accumulatedItems.fold(0.0, (acc, item) => acc + item.lineTotal);
  }

  // Quantité totale cumulée
  int get _grandTotalQuantity {
    return _accumulatedItems.fold(0, (acc, item) => acc + item.quantity);
  }

  int _quantity = 1;

  /// Ajoute la sélection en cours à la commande cumulée
  void _addCurrentSelectionToOrder() {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un produit.')),
      );
      return;
    }

    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le code produit doit comporter exactement 6 lettres.')),
      );
      return;
    }

    final selectedOpts = _currentOptions.where((o) => o.isSelected).map((o) => o.copyWith()).toList();
    final item = OrderItem(
      id: 'ITEM-${DateTime.now().millisecondsSinceEpoch}-${_accumulatedItems.length + 1}',
      productCode: _selectedProduct!.code,
      productLabel: _selectedProduct!.label,
      category: _selectedProduct!.category,
      basePrice: _selectedProduct!.basePrice,
      quantity: _quantity,
      selectedOptions: selectedOpts,
      unitPrice: _currentUnitPrice,
      lineTotal: _currentLineTotal,
    );

    setState(() {
      _accumulatedItems.add(item);
      _selectedProduct = null;
      _codeController.clear();
      _currentOptions = [];
      _quantity = 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Article ${item.productCode} ajouté (${_accumulatedItems.length} article(s) sélectionné(s)) !'),
        backgroundColor: Colors.blue.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Supprime un article
  void _removeAccumulatedItem(int index) {
    setState(() {
      _accumulatedItems.removeAt(index);
    });
  }

  /// Vide le panier d'articles
  void _clearAccumulatedItems() {
    setState(() {
      _accumulatedItems.clear();
    });
  }

  /// Valide et synchronise l'ensemble de la commande cumulée
  Future<void> _submitAndSyncCumulativeOrder() async {
    // Si aucun article cumulé mais qu'un produit est actuellement configuré, on le prend en compte
    if (_accumulatedItems.isEmpty) {
      if (_selectedProduct != null) {
        _addCurrentSelectionToOrder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez ajouter au moins un produit à la sélection.')),
        );
        return;
      }
    }

    // Dialogue Material 3 de validation récapitulant toutes les lignes cumulées
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Color(0xFF1E40AF)),
            const SizedBox(width: 8),
            Text('Validation sélection (${_accumulatedItems.length} art.)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Articles sélectionnés :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _accumulatedItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (context, i) {
                    final it = _accumulatedItems[i];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${it.productCode} - ${it.productLabel}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Qté: ${it.quantity > 0 ? "+${it.quantity}" : "${it.quantity}"} × ${it.unitPrice.toStringAsFixed(2)} € · ${it.selectedOptions.length} opt.', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                            ],
                          ),
                        ),
                        //Text('${it.lineTotal.toStringAsFixed(2)} €', style: TextStyle(fontWeight: FontWeight.bold, color: it.lineTotal < 0 ? Colors.orange.shade800 : Colors.blue.shade900)),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Quantité totale :', style: TextStyle(fontSize: 13)),
                  Text('$_grandTotalQuantity unités', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              /*Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Montant Total TTC :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${_grandTotalPrice.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E40AF))),
                ],
              ),*/
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Modifier')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text('Confirmer & Synchroniser ERP'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Enregistrement SQLite & synchronisation ERP en cours...';
    });

    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final itemsToSend = List<OrderItem>.from(_accumulatedItems);
    final totalToSend = _grandTotalPrice;
    final totalQtyToSend = _grandTotalQuantity;

    // 1. Création de la commande locale avec articles cumulés
    final order = OrderRecord(
      id: orderId,
      items: itemsToSend,
      totalPrice: totalToSend,
      totalQuantity: totalQtyToSend,
      customerRef: _customerController.text.trim(),
      notes: _notesController.text.trim(),
      createdAt: DateTime.now(),
      syncStatus: 'pending',
    );

    // 2. Enregistrement local immédiat dans la base SQLite (garantit le offline)
    await dbHelper.insertOrder(order);

    // 3. Appel de l'API REST en temps réel avec le payload complet des items
    //final syncResult = await ApiService.syncOrder(order);
    final syncResult = await ApiService.syncStockMovements(order);

    // 4. Mise à jour SQLite du statut retourné par l'API REST
    await dbHelper.updateSyncStatus(
      orderId: orderId,
      status: syncResult.success ? 'synced' : 'failed',
      syncTimestamp: DateTime.now(),
      apiResponse: syncResult.message,
    );

    setState(() {
      _isSyncing = false;
      _syncSuccess = syncResult.success;
      _syncStatusMessage = syncResult.success
          ? 'Sélection (${itemsToSend.length} article(s)) synchronisée ERP !'
          : 'Échec REST : ${syncResult.message}. Enregistrée dans SQLite en attente.';
      if (syncResult.success) {
        _accumulatedItems.clear(); // Vider le panier après synchronisation
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: syncResult.success ? Colors.green.shade700 : Colors.orange.shade800,
          content: Text(_syncStatusMessage!),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('pepStock', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Historique SQLite',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bandeau d'état de source & mode secours Dolibarr / JSON Local
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _isFallbackMode ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isFallbackMode ? Colors.orange.shade300 : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isFallbackMode ? Icons.warning_amber_rounded : Icons.cloud_done_rounded,
                      color: _isFallbackMode ? Colors.orange.shade800 : Colors.blue.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _catalogSource,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _isFallbackMode ? Colors.orange.shade900 : Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            _isFallbackMode
                                ? 'ERP injoignable : utilisation du catalogue local'
                                : 'Catalogue synchronisé ERP',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Retenter ERP',
                      onPressed: _initCatalogWithFallback,
                    ),
                  ],
                ),
              ),

              // Section 1 : Autocomplete Code Produit 6 Lettres
              const Text(
                'Code Produit (6 lettres)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              Autocomplete<Product>(
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<Product>.empty();
                  }
                  return await dbHelper.searchProducts(textEditingValue.text);
                },
                displayStringForOption: (Product product) => '${product.code} - ${product.label}',
                onSelected: _onProductSelected,
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Ex : AGAFAL, AEBLBE...',
                      prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                controller.clear();
                                setState(() {
                                  _selectedProduct = null;
                                  _currentOptions = [];
                                });
                              },
                            )
                          : null,
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 32,
                          maxHeight: 260,
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: options.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = options.elementAt(index);
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  product.code,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                              title: Text(product.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${product.category} · ${product.basePrice.toStringAsFixed(2)} €'),
                                  Text(
                                    'Stock disponible : ${product.stock.toStringAsFixed(0)} unités',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: product.stock > 10 ? Colors.green.shade700 : (product.stock > 0 ? Colors.orange.shade800 : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => onSelected(product),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Section Quantité (Liste déroulante de -20 à 20)
              const Text(
                'Quantité (-20 à +20)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _quantity,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.format_list_numbered_rounded),
                  helperText: '',
                ),
                items: List.generate(41, (i) => i - 20)
                    .map((qty) => DropdownMenuItem(
                          value: qty,
                          child: Text(
                            qty > 0
                                ? '+$qty '
                                : qty == 0
                                ? '0'
                                : '$qty',
                            style: TextStyle(
                              color: qty < 0 ? Colors.orange.shade800 : (qty > 0 ? Colors.blue.shade900 : Colors.grey),
                              fontWeight: qty != 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _quantity = val ?? 1;
                  });
                },
              ),

              const SizedBox(height: 20),

              // Détail du produit sélectionné
              if (_selectedProduct != null) ...[
                Card(
                  elevation: 0,
                  color: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedProduct!.label,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                /*Text(
                                  '${_selectedProduct!.basePrice.toStringAsFixed(2)} €',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                                ),*/
                                Text(
                                  'Stock : ${_selectedProduct!.stock.toStringAsFixed(0)} dispo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedProduct!.stock > 10 ? Colors.green.shade700 : Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_selectedProduct!.description, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Section 2 : Options dynamiques à cocher
                const Text(
                  'Options de variante',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                ...List.generate(_currentOptions.length, (index) {
                  final option = _currentOptions[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: option.isSelected ? Colors.blue.shade50.withOpacity(0.5) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: option.isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        value: option.isSelected,
                        title: Text(option.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          option.desc.isNotEmpty ? '${option.desc} (+ ${option.price.toStringAsFixed(2)} €)' : '+ ${option.price.toStringAsFixed(2)} €',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        secondary: Text(
                          '+${option.price.toStringAsFixed(2)} €',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: option.isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            option.isSelected = val ?? false;
                          });
                        },
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // Champs complémentaires
                /*TextField(
                  controller: _customerController,
                  decoration: const InputDecoration(
                    labelText: 'Référence client / Nom atelier',
                    hintText: 'Ex: Atelier Nord #402',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),*/
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Remarques',
                    hintText: '...',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),

                const SizedBox(height: 20),

                // Récapitulatif de la sélection en cours & Boutons d'action
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              //const Text('Sous-total article en cours :', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              Text('Qté: $_quantity × ${_currentUnitPrice.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Text(
                            '${_currentLineTotal.toStringAsFixed(2)} €',
                            style: TextStyle(
                              color: _currentLineTotal < 0 ? Colors.orange.shade800 : const Color(0xFF1E40AF),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E40AF),
                            foregroundColor: Colors.white,
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _addCurrentSelectionToOrder,
                          icon: const Icon(Icons.add_shopping_cart_rounded),
                          label: const Text(
                            'Ajouter cette sélection',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                      if (_accumulatedItems.isEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: _isSyncing ? null : _submitAndSyncCumulativeOrder,
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('Synchro ERP immédiate pour cet article', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Section Panier : Liste des articles cumulés avant validation globale
              if (_accumulatedItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shopping_cart_checkout_rounded, color: Color(0xFF1E40AF)),
                                const SizedBox(width: 8),
                                Text(
                                  'Articles sélectionnés (${_accumulatedItems.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _clearAccumulatedItems,
                              icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.red),
                              label: const Text('Vider', style: TextStyle(color: Colors.red, fontSize: 12)),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        ...List.generate(_accumulatedItems.length, (idx) {
                          final it = _accumulatedItems[idx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: Text(it.productCode, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(it.productLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text('Qté: ${it.quantity > 0 ? "+${it.quantity}" : "${it.quantity}"} × ${it.unitPrice.toStringAsFixed(2)} € · ${it.selectedOptions.length} opt.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${it.lineTotal.toStringAsFixed(2)} €',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: it.lineTotal < 0 ? Colors.orange.shade800 : Colors.blue.shade900),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                                  tooltip: 'Retirer cet article',
                                  onPressed: () => _removeAccumulatedItem(idx),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Quantité totale :', style: TextStyle(fontSize: 13)),
                            Text('$_grandTotalQuantity unités', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        /*Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Général TTC :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('${_grandTotalPrice.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1E40AF))),
                          ],
                        ),*/
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E40AF),
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isSyncing ? null : _submitAndSyncCumulativeOrder,
                            icon: _isSyncing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.cloud_upload_rounded),
                            label: Text(
                              _isSyncing ? 'Synchronisation...' : 'Valider la sélection (${_accumulatedItems.length} article(s))',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              /*if (_selectedProduct == null && _accumulatedItems.isEmpty) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(
                      children: [
                        Icon(Icons.manage_search_rounded, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Saisissez un code produit de 6 lettres',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choisissez dans le menu déroulant et précisez les variantes en options.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],*/
            ],
          ),
        ),
      ),
    );
  }
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique SQLite & Statut API REST')),
      body: FutureBuilder<List<OrderRecord>>(
        future: DatabaseHelper.instance.getOrders(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data!;
          if (orders.isEmpty) {
            return const Center(child: Text('Aucune sélection enregistrée en base SQLite.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final o = orders[index];
              final isSynced = o.syncStatus == 'synced';
              return Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${o.productCode} · ${o.productLabel}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            isSynced ? 'SYNCHRONISÉ' : 'EN ATTENTE',
                            style: TextStyle(
                              color: isSynced ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Options (${o.selectedOptions.length}) : ' + o.selectedOptions.map((e) => e.label).join(', ')),
                      const SizedBox(height: 4),
                      Text('Total: ${o.totalPrice.toStringAsFixed(2)} € · ${o.createdAt.toString().substring(0, 16)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
