import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/logger.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  final ThermalPrinterService _printerService = ThermalPrinterService();
  String? _savedAddress;
  String? _savedName;
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  StreamSubscription? _discoverySubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedPrinter() async {
    final address = await _printerService.getSavedPrinterAddress();
    final name = await _printerService.getSavedPrinterName();
    setState(() {
      _savedAddress = address;
      _savedName = name;
    });
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);
    if (!allGranted && mounted) {
      final permaDenied = statuses.values.any((s) => s.isPermanentlyDenied);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(permaDenied
              ? 'Bluetooth permissions denied. Please enable in Settings.'
              : 'Bluetooth permissions required.'),
          action: permaDenied
              ? SnackBarAction(label: 'Settings', onPressed: () => openAppSettings())
              : null,
          backgroundColor: Colors.red,
        ),
      );
    }
    return allGranted;
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    try {
      _discoverySubscription?.cancel();
      _discoverySubscription = FlutterBluetoothPrinter.discovery.listen(
        (dynamic state) {
          try {
            final devices = (state as dynamic).devices as List<BluetoothDevice>;
            setState(() {
              _devices = devices;
            });
          } catch (e) {
            Logger.warning('Failed to parse Bluetooth discovery results: $e');
          }
        },
        onError: (e) {
          setState(() => _isScanning = false);
          Logger.error('Discovery error', e);
        },
      );

      // Stop scanning after 10 seconds
      await Future.delayed(const Duration(seconds: 10));
      _discoverySubscription?.cancel();
      setState(() => _isScanning = false);
    } catch (e) {
      setState(() => _isScanning = false);
      Logger.error('scanDevices', e);
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    try {
      await _printerService.savePrinter(device.address, device.name ?? 'Unknown');
      await _loadSavedPrinter();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.name ?? device.address}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _testPrint() async {
    final success = await _printerService.printText(
      '--- TEST PRINT ---\n\nIdeal Store POS\nPrinter connected!\n\n${DateTime.now()}\n\n--- END ---\n',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Test print sent!' : 'Print failed — check connection'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    if (_savedAddress != null) {
      await FlutterBluetoothPrinter.disconnect(_savedAddress!);
    }
    await _printerService.clearPrinter();
    await _loadSavedPrinter();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer disconnected'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _connectByMac() async {
    final controller = TextEditingController(text: 'A8:29:00:00:69:A6');
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect by MAC Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter printer Bluetooth MAC address:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'MAC Address',
                hintText: 'XX:XX:XX:XX:XX:XX',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (address != null && address.isNotEmpty) {
      await _printerService.savePrinter(address, 'Printer ($address)');
      await _loadSavedPrinter();

      // Try to connect
      try {
        await FlutterBluetoothPrinter.connect(address);
      } catch (e) {
        Logger.warning('Failed to connect to printer at $address: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Printer saved: $address'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Setup'),
        actions: [
          if (_savedAddress != null)
            IconButton(
              icon: const Icon(Icons.print, color: Colors.green),
              onPressed: _testPrint,
              tooltip: 'Test Print',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current printer
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Printer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_savedAddress != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.print, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_savedName ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(_savedAddress!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _disconnect,
                          child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _testPrint,
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Test Print'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ),
                  ] else ...[
                    const Row(
                      children: [
                        Icon(Icons.print_disabled, color: Colors.grey, size: 20),
                        SizedBox(width: 8),
                        Text('No printer connected', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanDevices,
              icon: _isScanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bluetooth_searching, size: 18),
              label: Text(_isScanning ? 'Scanning...' : 'Scan for Printers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667eea),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _connectByMac,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Connect by MAC Address'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Discovered devices
          if (_devices.isNotEmpty) ...[
            Text('Found ${_devices.length} device(s)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._devices.map((device) => Card(
              child: ListTile(
                leading: Icon(
                  _savedAddress == device.address ? Icons.print : Icons.bluetooth,
                  color: _savedAddress == device.address ? Colors.green : const Color(0xFF667eea),
                ),
                title: Text(device.name ?? 'Unknown Device'),
                subtitle: Text(device.address, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: _savedAddress == device.address
                    ? const Chip(label: Text('Connected', style: TextStyle(fontSize: 10)), backgroundColor: Colors.green)
                    : const Icon(Icons.chevron_right),
                onTap: () => _connectDevice(device),
              ),
            )),
          ],

          if (_devices.isEmpty && !_isScanning) ...[
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('No printers found', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text('Make sure printer is on and paired in Android settings',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
