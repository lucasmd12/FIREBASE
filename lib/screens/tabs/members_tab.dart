import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucasbeatsfederacao/providers/auth_provider.dart';
import 'package:lucasbeatsfederacao/services/clan_service.dart';
import 'package:lucasbeatsfederacao/services/invite_service.dart';
import 'package:lucasbeatsfederacao/services/user_service.dart';
import 'package:lucasbeatsfederacao/models/member_model.dart';
import 'package:lucasbeatsfederacao/models/role_model.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';
import 'package:lucasbeatsfederacao/widgets/member_list_item.dart';

class MembersTab extends StatefulWidget {
  final String clanId;

  const MembersTab({super.key, required this.clanId});

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  List<Member> _members = [];
  List<Member> _filteredMembers = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _inviteEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _searchController.addListener(_filterMembers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final clanService = Provider.of<ClanService>(context, listen: false);

      final members = await clanService.getClanMembers(widget.clanId);
      
      if (mounted) {
        setState(() {
          _members = members;
          _filteredMembers = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Erro ao carregar membros', error: e);
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar membros: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _filterMembers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMembers = _members.where((member) {
        return member.username.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convidar Novo Membro'),
        content: TextField(
          controller: _inviteEmailController,
          decoration: const InputDecoration(
            labelText: 'Email do Usuário',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _sendInvite,
            child: const Text('Enviar Convite'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvite() async {
    Navigator.pop(context); // Fechar o diálogo
    final email = _inviteEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, insira um email.')), 
      );
      return;
    }

    try {
      final userService = UserService(); // Instanciar UserService
      final user = await userService.getUserByEmail(email); // Buscar usuário pelo email

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário com este email não encontrado.')), 
        );
        return;
      }

      final inviteService = InviteService();
      await inviteService.createInvite(user.id, 'clan', widget.clanId); // Usar o ID do usuário encontrado
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite enviado com sucesso!')), 
      );
      _inviteEmailController.clear();
    } catch (e) {
      Logger.error('Erro ao enviar convite', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar convite: ${e.toString()}')), 
      );
    }
  }

  void _handleMemberAction(Member member, String action) {
    switch (action) {
      case 'promote':
        _promoteMember(member);
        break;
      case 'demote':
        _demoteMember(member);
        break;
      case 'remove':
        _removeMember(member);
        break;
      case 'message':
        _sendMessage(member);
        break;
    }
  }

  void _promoteMember(Member member) async {
    try {
      final clanService = Provider.of<ClanService>(context, listen: false);
      await clanService.promoteMember(member.id); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Membro ${member.username} promovido com sucesso!')), 
      );
      _loadMembers();
    } catch (e) {
      Logger.error('Erro ao promover membro', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao promover membro: ${e.toString()}')), 
      );
    }
  }

  void _demoteMember(Member member) async {
    try {
      final clanService = Provider.of<ClanService>(context, listen: false);
      await clanService.demoteMember(member.id); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Membro ${member.username} rebaixado com sucesso!')), 
      );
      _loadMembers();
    } catch (e) {
      Logger.error('Erro ao rebaixar membro', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao rebaixar membro: ${e.toString()}')), 
      );
    }
  }

  void _removeMember(Member member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Membro'),
        content: Text('Tem certeza que deseja remover ${member.username} do clã?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final clanService = Provider.of<ClanService>(context, listen: false);
                await clanService.removeMember(member.id); 
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Membro ${member.username} removido com sucesso!')), 
                );
                _loadMembers();
              } catch (e) {
                Logger.error('Erro ao remover membro', error: e);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao remover membro: ${e.toString()}')), 
                );
              }
            },
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _sendMessage(Member member) {
    // Implementar envio de mensagem
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enviar mensagem para ${member.username} - Em desenvolvimento')), 
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final currentUser = authProvider.currentUser;
        
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadMembers();
                  },
                  child: const Text('Tentar Novamente'),
                ),
              ],
            ),
          );
        }

        final bool canManageMembers = currentUser?.clanRole == Role.clanLeader || currentUser?.clanRole == Role.clanSubLeader || currentUser?.role == Role.federationAdmin;

        return Column(
          children: [
            // Cabeçalho com busca e botão de convite
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Membros do Clã (${_members.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (canManageMembers) // Mostrar botão de convite apenas para quem pode gerenciar
                        ElevatedButton.icon(
                          onPressed: _showInviteDialog,
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Convidar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar membros...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade800.withValues(alpha: 0.8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Estatísticas rápidas
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade800.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Online',
                    '${_members.where((m) => m.isOnline).length}',
                    Colors.green,
                  ),
                  _buildStatItem(
                    'Líderes',
                    '${_members.where((m) => m.role == Role.clanLeader || m.role == Role.clanSubLeader).length}',
                    Colors.orange,
                  ),
                  _buildStatItem(
                    'Membros',
                    '${_members.where((m) => m.role == Role.clanMember).length}',
                    Colors.blue,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Lista de membros
            Expanded(
              child: _filteredMembers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty
                                ? 'Nenhum membro encontrado'
                                : 'Nenhum membro corresponde à busca',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMembers,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredMembers.length,
                        itemBuilder: (context, index) {
                          final member = _filteredMembers[index];
                          return MemberListItem(
                            member: member,
                            currentUser: currentUser!,
                            onMemberAction: _handleMemberAction,
                            canManage: canManageMembers,
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}


