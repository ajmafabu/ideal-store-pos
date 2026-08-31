import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profile.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../utils/pin_auth.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(staffListProvider),
        child: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (staff) {
          if (staff.isEmpty) {
            return const Center(child: Text('No staff found'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: staff.length,
            itemBuilder: (context, index) {
              final person = staff[index];
              final color = person.isAdmin ? const Color(0xFF667eea) : const Color(0xFF11998e);
              return Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      person.isAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: color,
                    ),
                  ),
                  title: Text(
                    person.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${person.isAdmin ? "Admin" : "Staff"} ${person.active ? "" : "(Inactive)"}',
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(person.active ? 'Deactivate' : 'Activate'),
                      ),
                      if (!person.isAdmin)
                        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                    onSelected: (value) => _handleAction(context, ref, person, value),
                  ),
                ),
              );
            },
          );
        },
      ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667eea).withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _addStaff(context, ref),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.person_add, color: Colors.white),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, Profile person, String action) async {
    switch (action) {
      case 'edit':
        _editStaff(context, ref, person);
        break;
      case 'toggle':
        await Supabase.instance.client
            .from('profiles')
            .update({'active': !person.active})
            .eq('id', person.id);
        if (context.mounted) ref.invalidate(staffListProvider);
        break;
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Staff'),
            content: Text('Delete "${person.name}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await Supabase.instance.client.from('profiles').delete().eq('id', person.id);
          if (context.mounted) ref.invalidate(staffListProvider);
        }
        break;
    }
  }

  void _addStaff(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _StaffForm(
        onSave: (name, email, password, pin) async {
          try {
            final auth = ref.read(authServiceProvider);

            if (pin.isNotEmpty) {
              await auth.signUpWithPin(
                email: email,
                pin: pin,
                name: name,
                role: 'staff',
              );
            } else {
              await auth.signUp(
                email: email,
                password: password,
                name: name,
                role: 'staff',
              );
            }

            ref.invalidate(staffListProvider);
            if (context.mounted) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Staff added')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _editStaff(BuildContext context, WidgetRef ref, Profile person) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _StaffForm(
        existingName: person.name,
        existingPin: person.pin,
        isEdit: true,
        onSave: (name, email, password, pin) async {
          try {
            await Supabase.instance.client
                .from('profiles')
                .update({
                  'name': name,
                  'pin': pin.isEmpty ? null : PinAuth.hashPin(pin),
                })
                .eq('id', person.id);

            ref.invalidate(staffListProvider);
            if (context.mounted) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Staff updated')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        },
      ),
    );
  }
}

class _StaffForm extends StatefulWidget {
  final String? existingName;
  final String? existingPin;
  final bool isEdit;
  final Future<void> Function(String name, String email, String password, String pin) onSave;

  const _StaffForm({
    this.existingName,
    this.existingPin,
    this.isEdit = false,
    required this.onSave,
  });

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingName ?? '');
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _pinController = TextEditingController(text: widget.existingPin ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isEdit ? 'Edit Staff' : 'Add Staff',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            if (!widget.isEdit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: 'PIN (for quick login)',
                border: OutlineInputBorder(),
                helperText: '4-6 digit PIN (used as password for quick login)',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => widget.onSave(
                _nameController.text,
                _emailController.text,
                _passwordController.text,
                _pinController.text,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(widget.isEdit ? 'Update' : 'Add Staff'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
