import 'package:lucasbeatsfederacao/services/api_service.dart';
import 'package:lucasbeatsfederacao/models/user_model.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';

class UserService {
  final ApiService _apiService = ApiService();

  Future<User?> getUserByEmail(String email) async {
    try {
      final response = await _apiService.get('/api/users/by-email?email=$email');
      if (response['success'] == true && response['data'] != null) {
        return User.fromJson(response['data']);
      } else {
        Logger.warning('Usuário com email $email não encontrado: ${response['msg']}');
        return null;
      }
    } catch (e) {
      Logger.error('Erro ao buscar usuário por email', error: e);
      return null;
    }
  }
}


