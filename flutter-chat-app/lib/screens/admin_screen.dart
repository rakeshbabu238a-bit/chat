import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../providers/auth_provider.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = true;
  bool _isCreating = false;
  String? _message;
  bool _isError = false;

  // User Links state
  List<Map<String, dynamic>> _links = [];
  bool _isLoadingLinks = true;
  final _linkLabelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadLinks();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _linkLabelController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final auth = context.read<AuthProvider>();
      final users = await auth.listUsers();
      setState(() {
        _users = users;
        _isLoadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingUsers = false;
        _message = 'Failed to load users';
        _isError = true;
      });
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _message = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      await auth.createUser(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim().isEmpty
            ? _emailController.text.split('@').first
            : _nameController.text.trim(),
      );

      // Auto-generate a dynamic link for the new user
      final label = _nameController.text.trim().isEmpty
          ? _emailController.text.split('@').first
          : _nameController.text.trim();
      final token = const Uuid().v4().replaceAll('-', '').substring(0, 12);
      await FirebaseFirestore.instance.collection('userLinks').doc(token).set({
        'label': label,
        'email': _emailController.text.trim(),
        'active': true,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'accessCount': 0,
      });

      setState(() {
        _message = 'User created! Link: ${_getLinkUrl(token)}';
        _isError = false;
        _isCreating = false;
      });

      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
      _loadUsers();
      _loadLinks();
    } catch (e) {
      setState(() {
        _message = e.toString().replaceFirst('Exception: ', '');
        _isError = true;
        _isCreating = false;
      });
    }
  }

  Future<void> _deleteUser(String uid, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete user?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "$displayName" from the system?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final auth = context.read<AuthProvider>();
      await auth.deleteUser(uid);
      setState(() {
        _message = '"$displayName" deleted';
        _isError = false;
      });
      _loadUsers();
    } catch (e) {
      setState(() {
        _message = 'Failed to delete user';
        _isError = true;
      });
    }
  }

  // ── User Links methods ──

  Future<void> _loadLinks() async {
    setState(() => _isLoadingLinks = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('userLinks')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _links = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'label': data['label'] ?? '',
            'active': data['active'] ?? true,
            'createdAt': (data['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
            'accessCount': data['accessCount'] ?? 0,
          };
        }).toList();
        _isLoadingLinks = false;
      });
    } catch (e) {
      setState(() => _isLoadingLinks = false);
    }
  }

  Future<void> _generateLink() async {
    final label = _linkLabelController.text.trim();
    if (label.isEmpty) {
      setState(() {
        _message = 'Please enter a label for the link';
        _isError = true;
      });
      return;
    }

    final token = const Uuid().v4().replaceAll('-', '').substring(0, 12);

    await FirebaseFirestore.instance.collection('userLinks').doc(token).set({
      'label': label,
      'active': true,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'accessCount': 0,
    });

    _linkLabelController.clear();
    setState(() {
      _message = 'Link generated successfully';
      _isError = false;
    });
    _loadLinks();
  }

  Future<void> _deleteLink(String linkId) async {
    await FirebaseFirestore.instance.collection('userLinks').doc(linkId).delete();
    setState(() {
      _message = 'Link deleted';
      _isError = false;
    });
    _loadLinks();
  }

  Future<void> _toggleLink(String linkId, bool currentActive) async {
    await FirebaseFirestore.instance.collection('userLinks').doc(linkId).update({
      'active': !currentActive,
    });
    _loadLinks();
  }

  String _getLinkUrl(String token) {
    return 'https://pinnacle-tech.in/#/link/$token';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Admin Panel',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Message banner ──
            if (_message != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isError
                        ? Colors.redAccent.withOpacity(0.3)
                        : Colors.greenAccent.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isError ? Icons.error_outline : Icons.check_circle_outline,
                      color: _isError ? Colors.redAccent : Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: _isError ? Colors.redAccent : Colors.greenAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Create User Section ──
            _buildSectionTitle('Create New User'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildInput(
                      controller: _nameController,
                      label: 'Display Name',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 12),
                    _buildInput(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildInput(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: true,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isCreating ? null : _createUser,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isCreating
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create User',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Users List Section ──
            _buildSectionTitle('Users (${_users.length})'),
            const SizedBox(height: 12),

            if (_isLoadingUsers)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                ),
              )
            else if (_users.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No users found',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                ),
              )
            else
              ..._users.map((user) => _buildUserCard(user)),

            const SizedBox(height: 28),

            // ── User Links Section ──
            _buildSectionTitle('User Links (${_links.length})'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _linkLabelController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Link label (e.g. "John\'s link")',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                        prefixIcon: const Icon(Icons.link, color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF6366F1)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _generateLink,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Generate', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_isLoadingLinks)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                ),
              )
            else if (_links.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No links generated yet',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                ),
              )
            else
              ..._links.map((link) => _buildLinkCard(link)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white.withOpacity(0.6),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isAdmin = user['role'] == 'admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isAdmin
                ? const Color(0xFF6366F1).withOpacity(0.3)
                : const Color(0xFF10B981).withOpacity(0.2),
            child: Text(
              (user['displayName'] as String? ?? 'U')[0].toUpperCase(),
              style: TextStyle(
                color: isAdmin ? const Color(0xFF818CF8) : const Color(0xFF6EE7B7),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['displayName'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user['email'] ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isAdmin
                  ? const Color(0xFF6366F1).withOpacity(0.2)
                  : const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isAdmin ? 'Admin' : 'Reader',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isAdmin ? const Color(0xFF818CF8) : const Color(0xFF6EE7B7),
              ),
            ),
          ),
          if (!isAdmin) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () => _deleteUser(user['uid'], user['displayName'] ?? 'user'),
              tooltip: 'Delete user',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLinkCard(Map<String, dynamic> link) {
    final isActive = link['active'] as bool;
    final url = _getLinkUrl(link['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link,
                size: 18,
                color: isActive ? const Color(0xFF6366F1) : Colors.white30,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link['label'] ?? 'Unnamed',
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isActive ? 'Active' : 'Disabled',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? const Color(0xFF6EE7B7) : Colors.redAccent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${link['accessCount']} views',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.5),
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link copied to clipboard'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF1E293B),
                      ),
                    );
                  },
                  child: const Icon(Icons.copy, size: 16, color: Color(0xFF818CF8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _toggleLink(link['id'], isActive),
                icon: Icon(
                  isActive ? Icons.pause : Icons.play_arrow,
                  size: 16,
                  color: isActive ? Colors.amber : Colors.greenAccent,
                ),
                label: Text(
                  isActive ? 'Disable' : 'Enable',
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? Colors.amber : Colors.greenAccent,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _deleteLink(link['id']),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                label: const Text(
                  'Delete',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
