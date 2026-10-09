import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/error_messages.dart';
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
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(staffListProvider),
        child: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: ${ErrorMessages.parse(e)}')),
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
                    tooltip: 'Edit, activate or delete',
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(person.active ? 'Deactivate' : 'Activate'),
                      ),
                      if (!person.isAdmin)
                        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFC62828)))),
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
        // labelled: the bare icon was unclear (QA #84)
        child: FloatingActionButton.extended(
          onPressed: () => _addStaff(context, ref),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.person_add, color: Colors.white),
          label: const Text('Add staff', style: TextStyle(color: Colors.white)),
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
        try {
          await ref.read(authServiceProvider).setStaffActive(person.id, !person.active);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
            );
          }
        }
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
                child: const Text('Delete', style: TextStyle(color: Color(0xFFC62828))),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          try {
            await ref.read(authServiceProvider).deleteStaff(person.id);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
              );
            }
          }
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
            // separate connection: the admin stays signed in (#2)
            await ref.read(authServiceProvider).createStaffAccount(
              email: email,
              name: name,
              password: password,
              pin: pin,
            );

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
                SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
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
            await ref.read(authServiceProvider).renameStaff(person.id, name);
            // A PIN is part of the staff member's login password, which only
            // they can change (Change PIN after signing in). Changing just
            // the stored hash here used to lock them out.
            final pinChanged = pin.isNotEmpty && (person.pin == null || !PinAuth.verifyPin(pin, person.pin!));
            if (pinChanged && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Name saved. The PIN can only be changed by that person: after signing in, tap the round button at the top of the dashboard → Change my PIN.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }

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
                SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
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
    // never put the stored PIN hash in a text box: it was shown in full and a
    // 4-6 digit PIN is recovered from its hash in seconds (QA #81)
    _pinController = TextEditingController();
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
            if (widget.isEdit)
              Text(
                widget.existingPin == null
                    ? 'No quick-login PIN set.'
                    : 'Quick-login PIN is set. Only that person can change it: dashboard → round button at the top → Change my PIN.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              TextField(
                controller: _pinController,
                obscureText: true,
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
