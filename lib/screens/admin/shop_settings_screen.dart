import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../services/thermal_printer_service.dart';

class ShopSettingsScreen extends ConsumerStatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  ConsumerState<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends ConsumerState<ShopSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _shopNameCtrl;
  late TextEditingController _gstinCtrl;
  late TextEditingController _shopAddressCtrl;
  late TextEditingController _shopPhoneCtrl;
  late TextEditingController _irnCtrl;
  bool _loading = false;
  String _printLanguage = 'english';
  bool _autoPrint = false;

  bool get useTamil =>
      _printLanguage == 'tamil' || _printLanguage == 'bilingual';
  bool get useEnglish =>
      _printLanguage == 'english' || _printLanguage == 'bilingual';

  @override
  void initState() {
    super.initState();
    final profileAsync = ref.read(profileProvider);
    final profile = profileAsync.value;
    _nameCtrl = TextEditingController(text: profile?.name ?? '');
    _shopNameCtrl = TextEditingController(text: profile?.shopName ?? '');
    _gstinCtrl = TextEditingController(text: profile?.gstin ?? '');
    _shopAddressCtrl = TextEditingController(text: profile?.shopAddress ?? '');
    _shopPhoneCtrl = TextEditingController(text: profile?.shopPhone ?? '');
    _irnCtrl = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final thermalService = ThermalPrinterService();
    setState(() {
      _printLanguage = prefs.getString('print_language') ?? 'english';
      _irnCtrl.text = prefs.getString('shop_irn') ?? '';
    });
    final autoPrint = await thermalService.getAutoPrint();
    if (mounted) setState(() => _autoPrint = autoPrint);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopNameCtrl.dispose();
    _gstinCtrl.dispose();
    _shopAddressCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _irnCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('print_language', _printLanguage);
      if (_irnCtrl.text.trim().isNotEmpty) {
        await prefs.setString('shop_irn', _irnCtrl.text.trim());
      } else {
        await prefs.remove('shop_irn');
      }
      final auth = ref.read(authServiceProvider);
      await auth.updateProfile(
        name: _nameCtrl.text.trim(),
        gstin: _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim(),
        shopName: _shopNameCtrl.text.trim().isEmpty
            ? null
            : _shopNameCtrl.text.trim(),
        shopAddress: _shopAddressCtrl.text.trim().isEmpty
            ? null
            : _shopAddressCtrl.text.trim(),
        shopPhone: _shopPhoneCtrl.text.trim().isEmpty
            ? null
            : _shopPhoneCtrl.text.trim(),
      );
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shop settings saved'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Shop Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shop Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.store_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text(
                      'Shop Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Shop Name
              _buildField(
                _shopNameCtrl,
                'Shop Name',
                Icons.store,
                'e.g. Ideal Store',
              ),

              const SizedBox(height: 16),

              // Your Name
              _buildField(_nameCtrl, 'Your Name', Icons.person, 'Admin name'),

              const SizedBox(height: 16),

              // Print Language
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.language_rounded,
                          color: Color(0xFF667eea),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Print Language',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('English'),
                            value: 'english',
                            groupValue: _printLanguage,
                            onChanged: (v) =>
                                setState(() => _printLanguage = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('தமிழ் (Tamil)'),
                            value: 'tamil',
                            groupValue: _printLanguage,
                            onChanged: (v) =>
                                setState(() => _printLanguage = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Bilingual'),
                            value: 'bilingual',
                            groupValue: _printLanguage,
                            onChanged: (v) =>
                                setState(() => _printLanguage = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Printer Setup
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.print, color: Color(0xFF667eea), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Printer Setup',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<String?>(
                      future: ThermalPrinterService().getSavedPrinterName(),
                      builder: (context, snapshot) {
                        final printerName = snapshot.data;
                        return Column(
                          children: [
                            if (printerName != null && printerName.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.print,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Saved Printer',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            printerName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        await ThermalPrinterService()
                                            .clearPrinter();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Printer removed'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                          setState(() {});
                                        }
                                      },
                                      tooltip: 'Remove printer',
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'No printer configured',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final printer =
                                          await ThermalPrinterService()
                                              .selectPrinter(context);
                                      if (printer != null && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Printer saved: ${printer.name}',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        setState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Setup Printer'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF667eea),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final service = ThermalPrinterService();
                                      await service.printDirect(
                                        'TEST PRINT\nTVS RP3200\nசக்ரா கோல்ட்\n${DateTime.now()}',
                                        title: 'Test Print',
                                        hasTamil: true,
                                      );
                                    },
                                    icon: const Icon(Icons.print, size: 18),
                                    label: const Text('Test Print'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Auto-print toggle
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _autoPrint
                                    ? Colors.green.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _autoPrint
                                      ? Colors.green.shade200
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _autoPrint
                                        ? Icons.print
                                        : Icons.print_disabled,
                                    color: _autoPrint
                                        ? Colors.green
                                        : Colors.grey,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Auto-Print',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _autoPrint
                                              ? 'Receipts print automatically (no dialog)'
                                              : 'Shows print dialog each time',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _autoPrint,
                                    onChanged: (v) async {
                                      await ThermalPrinterService()
                                          .setAutoPrint(v);
                                      setState(() => _autoPrint = v);
                                    },
                                    activeColor: Colors.green,
                                  ),
                                ],
                              ),
                            ),
                            if (_autoPrint) ...[
                              const SizedBox(height: 8),
                              FutureBuilder<String?>(
                                future: ThermalPrinterService()
                                    .getSavedWindowsPrinter(),
                                builder: (context, snapshot) {
                                  final printerName = snapshot.data;
                                  if (printerName == null ||
                                      printerName.isEmpty) {
                                    return Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.warning,
                                            color: Colors.orange.shade700,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'Select a Windows printer first for auto-print',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.print,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Auto-printing to: $printerName',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // GST Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.receipt_rounded,
                          color: Color(0xFF667eea),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'GST Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // GSTIN
                    TextFormField(
                      controller: _gstinCtrl,
                      decoration: InputDecoration(
                        labelText: 'GSTIN',
                        hintText: 'e.g. 27AAPFU0939F1ZV',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(
                          Icons.confirmation_number_rounded,
                        ),
                        counterText: '${_gstinCtrl.text.length}/15',
                      ),
                      maxLength: 15,
                      textCapitalization: TextCapitalization.characters,
                    ),

                    const SizedBox(height: 12),

                    // Shop Address
                    TextFormField(
                      controller: _shopAddressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Shop Address',
                        hintText: 'Full address for GST invoices',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on_rounded),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Shop Phone
                    TextFormField(
                      controller: _shopPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Shop Phone',
                        hintText: 'Phone number for invoices',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // E-Invoice IRN
                    TextFormField(
                      controller: _irnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'IRN (Invoice Reference Number)',
                        hintText: 'Optional - for e-invoicing',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code_rounded),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'IRN will be displayed on invoices for e-invoicing compliance. Leave empty if not applicable.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Colors.blue,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GSTIN and shop details will appear on invoices and tax reports',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667eea),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    String hint,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          prefixIcon: Icon(icon, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}
