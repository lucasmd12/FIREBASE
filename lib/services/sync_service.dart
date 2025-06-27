// lib/services/sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:lucasbeatsfederacao/services/api_service.dart';
import 'package:lucasbeatsfederacao/services/cache_service.dart';
import 'package:lucasbeatsfederacao/services/socket_service.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';

class SyncService {
  final ApiService _apiService;
  final SocketService _socketService;
  
  // Controle de sincronização
  bool _isInitialized = false;
  bool _isSyncing = false;
  Timer? _periodicSyncTimer;
  Timer? _healthCheckTimer;
  
  // Configurações
  static const Duration _syncInterval = Duration(minutes: 5);
  static const Duration _healthCheckInterval = Duration(minutes: 2);
  static const Duration _syncTimeout = Duration(seconds: 30);
  
  // Métricas
  int _syncCount = 0;
  int _syncErrors = 0;
  DateTime? _lastSyncTime;
  String _syncStatus = 'idle';

  SyncService(this._apiService, this._socketService);

  /// Inicializa o serviço de sincronização
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      Logger.info('Initializing sync service...');
      
      // Configurar listeners de eventos do Socket.IO
      _setupSocketListeners();
      
      // Iniciar sincronização periódica
      _startPeriodicSync();
      
      // Iniciar health check
      _startHealthCheck();
      
      // Sincronização inicial
      await _performInitialSync();
      
      _isInitialized = true;
      Logger.info('Sync service initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize sync service: $e');
      rethrow;
    }
  }

  /// Configura listeners para eventos de invalidação do Socket.IO
  void _setupSocketListeners() {
    try {
      // Evento de invalidação de cache
      _socketService.on('cache_invalidated', (data) {
        _handleCacheInvalidation(data);
      });
      
      // Evento de atualização de dados
      _socketService.on('data_updated', (data) {
        _handleDataUpdate(data);
      });
      
      // Evento de usuário online/offline
      _socketService.on('user_online', (userId) {
        _handleUserStatusChange(userId, true);
      });
      
      _socketService.on('user_offline', (userId) {
        _handleUserStatusChange(userId, false);
      });
      
      // Eventos específicos de entidades
      _socketService.on('clan_updated', (data) {
        _handleClanUpdate(data);
      });
      
      _socketService.on('federation_updated', (data) {
        _handleFederationUpdate(data);
      });
      
      _socketService.on('mission_updated', (data) {
        _handleMissionUpdate(data);
      });
      
      Logger.info('Socket listeners configured for sync service');
    } catch (e) {
      Logger.error('Error setting up socket listeners: $e');
    }
  }

  /// Inicia sincronização periódica
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_syncInterval, (timer) {
      _performPeriodicSync();
    });
    Logger.info('Periodic sync started (interval: ${_syncInterval.inMinutes}min)');
  }

  /// Inicia health check periódico
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      _performHealthCheck();
    });
    Logger.info('Health check started (interval: ${_healthCheckInterval.inMinutes}min)');
  }

  /// Realiza sincronização inicial
  Future<void> _performInitialSync() async {
    try {
      _syncStatus = 'initial_sync';
      Logger.info('Performing initial sync...');
      
      // Verificar dados essenciais em cache
      final needsUserSync = !await CacheService().isCacheValid('user');
      final needsStatsSync = !await CacheService().isCacheValid('stats');
      final needsFederationsSync = !await CacheService().isCacheValid('federations');
      
      // Sincronizar dados essenciais se necessário
      if (needsUserSync || needsStatsSync || needsFederationsSync) {
        await _syncEssentialData();
      }
      
      _syncStatus = 'idle';
      Logger.info('Initial sync completed');
    } catch (e) {
      _syncStatus = 'error';
      Logger.error('Initial sync failed: $e');
    }
  }

  /// Realiza sincronização periódica
  Future<void> _performPeriodicSync() async {
    if (_isSyncing) {
      Logger.debug('Sync already in progress, skipping periodic sync');
      return;
    }
    
    try {
      _isSyncing = true;
      _syncStatus = 'syncing';
      _syncCount++;
      
      Logger.info('Performing periodic sync...');
      
      // Limpar cache expirado
      await CacheService().clearExpiredCache();
      
      // Sincronizar dados que podem ter mudado
      await _syncVolatileData();
      
      _lastSyncTime = DateTime.now();
      _syncStatus = 'idle';
      Logger.debug('Periodic sync completed');
    } catch (e) {
      _syncErrors++;
      _syncStatus = 'error';
      Logger.error('Periodic sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Realiza health check
  Future<void> _performHealthCheck() async {
    try {
      // Verificar conectividade com backend
      await _apiService.get('/health', requireAuth: false, timeout: const Duration(seconds: 10));
      
      // Verificar saúde do cache local
      final cacheHealth = await CacheService().getHealthInfo();
      
      if (cacheHealth['expiredEntries'] > 10) {
        Logger.info('Found ${cacheHealth['expiredEntries']} expired cache entries, cleaning up...');
        await CacheService().clearExpiredCache();
      }
      
    } catch (e) {
      Logger.warning('Health check failed: $e');
    }
  }

  /// Sincroniza dados essenciais
  Future<void> _syncEssentialData() async {
    try {
      // Sincronizar estatísticas globais
      await _syncGlobalStats();
      
      // Sincronizar federações
      await _syncFederations();
      
      Logger.info('Essential data sync completed');
    } catch (e) {
      Logger.error('Essential data sync failed: $e');
      rethrow;
    }
  }

  /// Sincroniza dados voláteis
  Future<void> _syncVolatileData() async {
    try {
      // Sincronizar apenas se cache estiver próximo do vencimento
      final statsValid = await CacheService().isCacheValid('stats');
      if (!statsValid) {
        await _syncGlobalStats();
      }
      
    } catch (e) {
      Logger.error('Volatile data sync failed: $e');
    }
  }

  /// Sincroniza estatísticas globais
  Future<void> _syncGlobalStats() async {
    try {
      final response = await _apiService.get('/cache/global');
      if (response['success'] == true) {
        await CacheService().cacheStats(response['data']);
        Logger.info('Global stats synced successfully');
      }
    } catch (e) {
      Logger.error('Failed to sync global stats: $e');
    }
  }

  /// Sincroniza federações
  Future<void> _syncFederations() async {
    try {
      final response = await _apiService.get('/federations');
      if (response['success'] == true) {
        await CacheService().cacheFederations(
          List<Map<String, dynamic>>.from(response['data'])
        );
        Logger.info('Federations synced successfully');
      }
    } catch (e) {
      Logger.error('Failed to sync federations: $e');
    }
  }

  /// Sincroniza clãs
  Future<void> _syncClans({String? federationId}) async {
    try {
      final endpoint = federationId != null 
        ? '/clans?federationId=$federationId'
        : '/clans';
      
      final response = await _apiService.get(endpoint);
      if (response['success'] == true) {
        await CacheService().cacheClans(
          List<Map<String, dynamic>>.from(response['data']),
          federationId: federationId
        );
        Logger.info('Clans synced successfully${federationId != null ? ' for federation $federationId' : ''}');
      }
    } catch (e) {
      Logger.error('Failed to sync clans: $e');
    }
  }

  /// Manipula invalidação de cache
  void _handleCacheInvalidation(dynamic data) {
    try {
      final invalidationData = data as Map<String, dynamic>;
      final type = invalidationData['type'] as String?;
      final id = invalidationData['id'] as String?;
      
      if (type != null) {
        CacheService().invalidateCache(type, id: id);
        Logger.info('Cache invalidated for type: $type${id != null ? ' (id: $id)' : ''}');
      }
    } catch (e) {
      Logger.error('Error handling cache invalidation: $e');
    }
  }

  /// Manipula atualização de dados
  void _handleDataUpdate(dynamic data) {
    try {
      final updateData = data as Map<String, dynamic>;
      final type = updateData['type'] as String?;
      final payload = updateData['data'];
      
      switch (type) {
        case 'stats':
          if (payload != null) {
            CacheService().cacheStats(payload);
          }
          break;
        case 'user':
          // Invalidar cache do usuário para forçar reload
          CacheService().invalidateCache('user');
          break;
        default:
          Logger.info('Unhandled data update type: $type');
      }
    } catch (e) {
      Logger.error('Error handling data update: $e');
    }
  }

  /// Manipula mudança de status de usuário
  void _handleUserStatusChange(String userId, bool isOnline) {
    try {
      // Invalidar estatísticas para refletir mudança
      CacheService().invalidateCache('stats');
      Logger.info('User $userId status changed to ${isOnline ? 'online' : 'offline'}');
    } catch (e) {
      Logger.error('Error handling user status change: $e');
    }
  }

  /// Manipula atualização de clã
  void _handleClanUpdate(dynamic data) {
    try {
      final clanData = data as Map<String, dynamic>;
      final clanId = clanData['clanId'] as String?;
      
      if (clanId != null) {
        CacheService().invalidateClanRelated(clanId);
        Logger.info('Clan cache invalidated for clan: $clanId');
      }
    } catch (e) {
      Logger.error('Error handling clan update: $e');
    }
  }

  /// Manipula atualização de federação
  void _handleFederationUpdate(dynamic data) {
    try {
      final federationData = data as Map<String, dynamic>;
      final federationId = federationData['federationId'] as String?;
      
      if (federationId != null) {
        CacheService().invalidateFederationRelated(federationId);
        Logger.info('Federation cache invalidated for federation: $federationId');
      }
    } catch (e) {
      Logger.error('Error handling federation update: $e');
    }
  }

  /// Manipula atualização de missão
  void _handleMissionUpdate(dynamic data) {
    try {
      final missionData = data as Map<String, dynamic>;
      final clanId = missionData['clanId'] as String?;
      
      if (clanId != null) {
        CacheService().invalidateCache('missions', id: clanId);
        CacheService().invalidateCache('stats'); // Missões podem afetar estatísticas
        Logger.info('Mission cache invalidated for clan: $clanId');
      }
    } catch (e) {
      Logger.error('Error handling mission update: $e');
    }
  }

  /// Força sincronização manual
  Future<void> forceSync() async {
    if (_isSyncing) {
      Logger.warning('Sync already in progress');
      return;
    }

    try {
      _isSyncing = true;
      _syncStatus = 'manual_sync';
      
      // Limpar todo o cache e recarregar
      await CacheService().clearAllCache();
      await _syncEssentialData();
      
      _lastSyncTime = DateTime.now();
      _syncStatus = 'idle';
      Logger.info('Manual sync completed');
    } catch (e) {
      _syncErrors++;
      _syncStatus = 'error';
      Logger.error('Manual sync failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Obtém status da sincronização
  Map<String, dynamic> getSyncStatus() {
    return {
      'isInitialized': _isInitialized,
      'isSyncing': _isSyncing,
      'status': _syncStatus,
      'syncCount': _syncCount,
      'syncErrors': _syncErrors,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'nextSyncIn': _periodicSyncTimer != null 
        ? _syncInterval.inSeconds - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % _syncInterval.inSeconds
        : null,
    };
  }

  /// Para o serviço de sincronização
  void dispose() {
    _periodicSyncTimer?.cancel();
    _healthCheckTimer?.cancel();
    _isInitialized = false;
    Logger.info('Sync service disposed');
  }
}

