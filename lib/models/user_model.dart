import 'package:flutter/foundation.dart';
import 'package:lucasbeatsfederacao/models/role_model.dart'; // Importar Role

class User {
  final String id;
  final String username;
  final String? email; // Adicionado: Email pode ser nulo se não for usado
  final String avatar;
  final String bio;
  final String status;
  final String? clanId; // Pode ser nulo se não tiver clã
  final String? clanName; // Adicionado: Nome do clã
  final String? clanTag; // Adicionado: Tag do clã
  final Role clanRole; // Alterado para Role
  final String? federationId; // Pode ser nulo
  final String? federationName; // Adicionado: Nome da federação
  final String? federationTag; // Adicionado: Tag da federação
  final Role role; // Alterado para Role
  final bool online;
  final DateTime ultimaAtividade;
  final DateTime lastSeen;
  final DateTime? createdAt; // Adicionado: Data de criação do usuário

  User({
    required this.id,
    required this.username,
    this.email,
    this.avatar = 'default_avatar.png',
    this.bio = 'Sem biografia.',
    this.status = 'offline',
    this.clanId,
    this.clanName,
    this.clanTag,
    this.clanRole = Role.member, // Valor padrão como enum
    this.federationId,
    this.federationName,
    this.federationTag,
    this.role = Role.user, // Valor padrão como enum
    this.online = false,
    required this.ultimaAtividade,
    required this.lastSeen,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      avatar: json['avatar'] as String? ?? 'default_avatar.png',
      bio: json['bio'] as String? ?? 'Sem biografia.',
      status: json['status'] as String? ?? 'offline',
      clanId: json['clanId'] as String? ?? json['clan'] as String?, // Adicionado clanId e compatibilidade com 'clan'
      clanName: json['clanName'] as String?,
      clanTag: json['clanTag'] as String?,
      clanRole: roleFromString(json['clanRole'] as String?), // Convertendo para enum
      federationId: json['federationId'] as String? ?? json['federation'] as String?, // Adicionado federationId e compatibilidade com 'federation'
      federationName: json['federationName'] as String?,
      federationTag: json['federationTag'] as String?,
      role: roleFromString(json['role'] as String?), // Convertendo para enum
      online: json['online'] as bool? ?? false,
      ultimaAtividade: DateTime.parse(json['ultimaAtividade'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'bio': bio,
      'status': status,
      'clanId': clanId,
      'clanName': clanName,
      'clanTag': clanTag,
      'clanRole': roleToString(clanRole), // Convertendo de enum para string
      'federationId': federationId,
      'federationName': federationName,
      'federationTag': federationTag,
      'role': roleToString(role), // Convertendo de enum para string
      'online': online,
      'ultimaAtividade': ultimaAtividade.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  // Getter para isOnline (compatibilidade com backend)
  bool get isOnline => online; // Já existe a propriedade 'online'

  // Getter para tag (se houver um campo 'tag' no backend para o usuário)
  String? get tag => federationTag; // Usando federationTag como 'tag' se aplicável

  // Getter para 'clan' e 'federation' para compatibilidade com o código existente
  String? get clan => clanId;
  String? get federation => federationId;
}



