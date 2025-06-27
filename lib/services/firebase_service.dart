import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';
import 'package:lucasbeatsfederacao/services/api_service.dart';
import 'package:lucasbeatsfederacao/services/cache_service.dart';
import 'package:lucasbeatsfederacao/services/qrr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart'; // Importar para navegação
import 'package:lucasbeatsfederacao/main.dart'; // Importar para acesso ao navigatorKey
import 'package:lucasbeatsfederacao/screens/qrr_detail_screen.dart'; // Importar tela de detalhes da QRR
import 'package:firebase_database/firebase_database.dart';

// Handler para mensagens em background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  Logger.info('Background message received: ${message.messageId}');
  
  // Processar notificação em background se necessário
  if (message.notification != null) {
    Logger.info('Background notification: ${message.notification!.title}');
  }
}

class FirebaseService extends ChangeNotifier {
  static FirebaseService? _instance;
  
  factory FirebaseService([ApiService? apiService]) {
    _instance ??= FirebaseService._internal(apiService);
    return _instance!;
  }
  
  FirebaseService._internal(this._apiService);

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _localNotifications;
  ApiService? _apiService; // Removido final para permitir reatribuição
  CacheService? _cacheService;
  
  bool _initialized = false;
  String? _fcmToken;
  
  // Estatísticas
  int _notificationsReceived = 0;
  int _notificationsShown = 0;
  DateTime? _lastNotificationTime;
  
  // Configurações
  bool _notificationsEnabled = true;
  Map<String, bool> _notificationTypes = {
    'messages': true,
    'calls': true,
    'missions': true,
    'promotions': true,
    'system': true,
    'qrr': true, // Adicionado tipo QRR
  };

  /// Inicializa o Firebase e FCM
  Future<bool> initialize() async {
    try {
      if (_initialized) {
        Logger.info('Firebase service already initialized');
        return true;
      }

      // Inicializar Firebase
      await Firebase.initializeApp();
      
      // Inicializar FCM
      _messaging = FirebaseMessaging.instance;
      
      // Inicializar notificações locais
      await _initializeLocalNotifications();
      
      // Configurar handlers de mensagem
      await _setupMessageHandlers();
      
      // Solicitar permissões
      await _requestPermissions();
      
      // Obter token FCM
      await _getFCMToken();
      
      // Inicializar serviços auxiliares
      _apiService = ApiService(); // Atribuir aqui
      _cacheService = CacheService();
      
      // Carregar configurações
      await _loadSettings();
      
      _initialized = true;
      Logger.info("Firebase service initialized successfully");
      notifyListeners();
      return true;
    } catch (error) {
      Logger.error('Failed to initialize Firebase service: ${error.toString()}');
      return false;
    }
  }

  /// Inicializa notificações locais
  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();
    
    // Configurações Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Configurações iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Criar canal de notificação para Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  /// Cria canais de notificação para Android
  Future<void> _createNotificationChannels() async {
    const channels = [
      AndroidNotificationChannel(
        'default',
        'Notificações Gerais',
        description: 'Notificações gerais do aplicativo',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'messages',
        'Mensagens',
        description: 'Notificações de novas mensagens',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('message'),
      ),
      AndroidNotificationChannel(
        'calls',
        'Chamadas',
        description: 'Notificações de chamadas recebidas',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('call_ringtone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      ),
      AndroidNotificationChannel(
        'missions',
        'Missões',
        description: 'Notificações de novas missões',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'promotions',
        'Promoções',
        description: 'Notificações de promoções e conquistas',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'qrr',
        'QRR',
        description: 'Notificações relacionadas a missões QRR',
        importance: Importance.high,
      ),
    ];

    for (final channel in channels) {
      await _localNotifications!
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Configura handlers de mensagem
  Future<void> _setupMessageHandlers() async {
    // Handler para mensagens em background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Handler para mensagens quando app está em foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handler para quando usuário toca na notificação (app em background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
    // Verificar se app foi aberto por uma notificação
    final initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Solicita permissões de notificação
  Future<NotificationSettings> _requestPermissions() async {
    final settings = await _messaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true
    );
    
    Logger.info('Notification permission status: ${settings.authorizationStatus}');
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      Logger.info('User granted notification permissions');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      Logger.info('User granted provisional notification permissions');
    } else {
      Logger.warning('User declined or has not accepted notification permissions');
    }
    
    return settings;
  }

  /// Obtém token FCM
  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _messaging!.getToken();
      if (_fcmToken != null) {
        Logger.info('FCM Token obtained: ${_fcmToken!.substring(0, 20)}...');
        
        // Salvar token localmente
        await _saveTokenLocally(_fcmToken!);
        
        // Registrar token no backend
        await _registerTokenWithBackend(_fcmToken!);
      } else {
        Logger.error('Failed to obtain FCM token');
      }
    } catch (error) {
      Logger.error('Error getting FCM token: ${error.toString()}');
    }
  }

  /// Salva token localmente
  Future<void> _saveTokenLocally(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      await prefs.setString('fcm_token_timestamp', DateTime.now().toIso8601String());
    } catch (error) {
      Logger.error('Error saving FCM token locally: ${error.toString()}');
    }
  }

  /// Registra token no backend
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      if (_apiService == null) return;
      
      final deviceInfo = await _getDeviceInfo();
      
      final response = await _apiService!.post('/api/notifications/register-token', {
        'token': token,
        'deviceInfo': deviceInfo,
      });
      
      if (response["success"] == true) {
        Logger.info("FCM token registered with backend successfully");
        notifyListeners();
      } else {
        Logger.error('Failed to register FCM token with backend: ${response['message']}');
      }
    } catch (error) {
      Logger.error('Error registering FCM token with backend: ${error.toString()}');
    }
  }

  /// Obtém informações do dispositivo
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'deviceType': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'unknown',
      'osVersion': Platform.operatingSystemVersion,
      'appVersion': '2.1.0', // Versão do pubspec.yaml
      'language': Platform.localeName,
      'timezone': DateTime.now().timeZoneName,
    };
  }

  /// Handler para mensagens em foreground
  void _handleForegroundMessage(RemoteMessage message) {
    Logger.info('Foreground message received: ${message.messageId}');
    
    _notificationsReceived++;
    _lastNotificationTime = DateTime.now();
    
    // Verificar se deve mostrar notificação
    if (_shouldShowNotification(message)) {
      _showLocalNotification(message);
    }
    
    // Processar dados da mensagem
    _processMessageData(message);
  }

  /// Handler para quando usuário toca na notificação
  void _handleMessageOpenedApp(RemoteMessage message) {
    Logger.info('Message opened app: ${message.messageId}');
    
    // Processar ação baseada no tipo de notificação
    _handleNotificationAction(message);
  }

  /// Handler para quando usuário toca na notificação local
  void _onNotificationTapped(NotificationResponse response) {
    Logger.info('Local notification tapped: ${response.id}');
    
    // Processar payload se disponível
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        _handleNotificationActionFromData(data);
      } catch (error) {
        Logger.error('Error parsing notification payload: ${error.toString()}');
      }
    }
  }

  /// Verifica se deve mostrar notificação
  bool _shouldShowNotification(RemoteMessage message) {
    if (!_notificationsEnabled) return false;
    
    final messageType = message.data['type'] ?? 'system';
    return _notificationTypes[messageType] ?? true;
  }

  /// Mostra notificação local
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      if (_localNotifications == null) return;
      
      final notification = message.notification;
      if (notification == null) return;
      
      final messageType = message.data['type'] ?? 'default';
      final channelId = _getChannelIdForType(messageType);
      
      final androidDetails = AndroidNotificationDetails(
        channelId,
        _getChannelNameForType(messageType),
        channelDescription: _getChannelDescriptionForType(messageType),
        importance: _getImportanceForType(messageType),
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(notification.body ?? ''),
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _localNotifications!.show(
        message.hashCode,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(message.data),
      );
      
      _notificationsShown++;
      Logger.info('Local notification shown: ${notification.title}');
    } catch (error) {
      Logger.error('Error showing local notification: ${error.toString()}');
    }
  }

  /// Obtém ID do canal baseado no tipo
  String _getChannelIdForType(String type) {
    switch (type) {
      case 'new_message':
        return 'messages';
      case 'incoming_call':
        return 'calls';
      case 'new_mission':
      case 'qrr': // Adicionado tipo QRR
        return 'qrr';
      case 'promotion':
        return 'promotions';
      default:
        return 'default';
    }
  }

  /// Obtém nome do canal baseado no tipo
  String _getChannelNameForType(String type) {
    switch (type) {
      case 'new_message':
        return 'Mensagens';
      case 'incoming_call':
        return 'Chamadas';
      case 'new_mission':
      case 'qrr': // Adicionado tipo QRR
        return 'QRR';
      case 'promotion':
        return 'Promoções';
      default:
        return 'Notificações Gerais';
    }
  }

  /// Obtém descrição do canal baseado no tipo
  String _getChannelDescriptionForType(String type) {
    switch (type) {
      case 'new_message':
        return 'Notificações de novas mensagens';
      case 'incoming_call':
        return 'Notificações de chamadas recebidas';
      case 'new_mission':
      case 'qrr': // Adicionado tipo QRR
        return 'Notificações relacionadas a missões QRR';
      case 'promotion':
        return 'Notificações de promoções e conquistas';
      default:
        return 'Notificações gerais do aplicativo';
    }
  }

  /// Obtém importância baseada no tipo
  Importance _getImportanceForType(String type) {
    switch (type) {
      case 'incoming_call':
        return Importance.max;
      case 'new_message':
      case 'new_mission':
      case 'qrr': // Adicionado tipo QRR
      case 'promotion':
        return Importance.high;
      default:
        return Importance.defaultImportance;
    }
  }

  /// Processa dados da mensagem
  void _processMessageData(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];
    
    switch (type) {
      case 'new_message':
        _handleNewMessageData(data);
        break;
      case 'incoming_call':
        _handleIncomingCallData(data);
        break;
      case 'new_mission':
      case 'qrr': // Adicionado tipo QRR
        _handleNewMissionData(data);
        break;
      case 'promotion':
        _handlePromotionData(data);
        break;
      default:
        Logger.info('Unknown message type: $type');
    }
  }

  /// Processa dados de nova mensagem
  void _handleNewMessageData(Map<String, dynamic> data) {
    // Invalidar cache de mensagens
    _cacheService?.invalidatePattern('messages_*');
    
    // Atualizar badge de mensagens não lidas
    _updateUnreadMessagesBadge();
  }

  /// Processa dados de chamada recebida
  void _handleIncomingCallData(Map<String, dynamic> data) {
    final callerName = data['callerName'];
    final callType = data['callType'] ?? 'voice';
    
    Logger.info('Incoming call from $callerName (type: $callType)');
    
    // Aqui você pode integrar com a tela de chamada
    // Por exemplo, navegar para CallScreen ou mostrar overlay
  }

  /// Processa dados de nova missão (ou QRR)
  void _handleNewMissionData(Map<String, dynamic> data) {
    // Invalidar cache de missões
    _cacheService?.invalidatePattern('mission_*');
    _cacheService?.invalidatePattern('qrr_*'); // Invalidar cache de QRR
    
    final missionTitle = data['title'] ?? 'Nova Missão/QRR';
    final qrrId = data['qrrId'];

    if (qrrId != null) {
      // Navegar para a tela de detalhes da QRR
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => QRRDetailScreen(qrrId: qrrId),
          ),
        );
      }
    }
  }

  /// Processa dados de promoção
  void _handlePromotionData(Map<String, dynamic> data) {
    // Lógica para promoções
    Logger.info('Promotion data received: $data');
  }

  /// Processa ação de notificação
  void _handleNotificationAction(RemoteMessage message) {
    final data = message.data;
    _handleNotificationActionFromData(data);
  }

  /// Processa ação de notificação a partir de dados
  void _handleNotificationActionFromData(Map<String, dynamic> data) {
    final type = data['type'];
    final qrrId = data['qrrId'];

    switch (type) {
      case 'qrr':
        if (qrrId != null) {
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.push(
              MaterialPageRoute(
                builder: (context) => QRRDetailScreen(qrrId: qrrId),
              ),
            );
          }
        }
        break;
      // Adicionar outros tipos de ação aqui
      default:
        Logger.info('Unhandled notification action type: $type');
    }
  }

  /// Carrega configurações de notificação
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    _notificationTypes.forEach((key, value) {
      _notificationTypes[key] = prefs.getBool('notificationType_$key') ?? true;
    });
    notifyListeners();
  }

  /// Salva configurações de notificação
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
    for (final entry in _notificationTypes.entries) {
      await prefs.setBool('notificationType_${entry.key}', entry.value);
    }
    notifyListeners();
  }

  /// Obtém status de notificação
  bool get notificationsEnabled => _notificationsEnabled;

  /// Define status de notificação
  set notificationsEnabled(bool value) {
    _notificationsEnabled = value;
    saveSettings();
  }

  /// Obtém status de tipo de notificação
  bool getNotificationTypeStatus(String type) {
    return _notificationTypes[type] ?? true;
  }

  /// Define status de tipo de notificação
  void setNotificationTypeStatus(String type, bool status) {
    _notificationTypes[type] = status;
    saveSettings();
  }

  /// Obtém token FCM
  String? get fcmToken => _fcmToken;

  /// Obtém estatísticas de notificação
  Map<String, dynamic> getNotificationStats() {
    return {
      'received': _notificationsReceived,
      'shown': _notificationsShown,
      'lastTime': _lastNotificationTime?.toIso8601String(),
    };
  }

  /// Reseta estatísticas de notificação
  void resetNotificationStats() {
    _notificationsReceived = 0;
    _notificationsShown = 0;
    _lastNotificationTime = null;
    notifyListeners();
  }

  /// Atualiza badge de mensagens não lidas (exemplo)
  void _updateUnreadMessagesBadge() {
    // Lógica para atualizar o badge do aplicativo
    // Pode envolver consultar o backend ou um cache local
    Logger.info('Updating unread messages badge...');
  }

  // Métodos para salas de voz (Firebase Realtime Database)
  final DatabaseReference _voiceRoomsRef = FirebaseDatabase.instance.ref('voice_rooms');
  final DatabaseReference _usersOnlineRef = FirebaseDatabase.instance.ref('users_online');

  /// Cria uma nova sala de voz
  Future<void> createVoiceRoom({
    required String roomName,
    required String roomType,
    String? clanId,
    String? federationId,
    String? adminContext,
    bool isPrivate = false,
    String? password,
  }) async {
    try {
      final newRoomRef = _voiceRoomsRef.push();
      final roomId = newRoomRef.key;

      if (roomId == null) {
        throw Exception('Failed to generate room ID');
      }

      final roomData = {
        'roomId': roomId,
        'roomName': roomName,
        'roomType': roomType,
        'createdAt': ServerValue.timestamp,
        'isActive': true,
        'participants': {},
        'isPrivate': isPrivate,
        'password': password, // Armazenar senha (hash em um cenário real)
        'clanId': clanId,
        'federationId': federationId,
        'adminContext': adminContext,
      };

      await newRoomRef.set(roomData);
      Logger.info('Voice room created: $roomName ($roomId)');
    } catch (e, stackTrace) {
      Logger.error('Error creating voice room', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Entra em uma sala de voz
  Future<void> joinVoiceRoom(String roomId, String userId, String displayName) async {
    try {
      final roomParticipantsRef = _voiceRoomsRef.child(roomId).child('participants');
      await roomParticipantsRef.child(userId).set({
        'userId': userId,
        'displayName': displayName,
        'joinedAt': ServerValue.timestamp,
      });
      Logger.info('User $displayName joined room $roomId');
    } catch (e, stackTrace) {
      Logger.error('Error joining voice room', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Sai de uma sala de voz
  Future<void> leaveVoiceRoom(String roomId, String userId) async {
    try {
      final roomParticipantsRef = _voiceRoomsRef.child(roomId).child('participants');
      await roomParticipantsRef.child(userId).remove();
      Logger.info('User $userId left room $roomId');

      // Verificar se a sala ficou vazia e desativar
      final snapshot = await roomParticipantsRef.once();
      if (!snapshot.snapshot.exists || (snapshot.snapshot.value as Map).isEmpty) {
        await _voiceRoomsRef.child(roomId).update({'isActive': false});
        Logger.info('Voice room $roomId is now inactive (empty)');
      }
    } catch (e, stackTrace) {
      Logger.error('Error leaving voice room', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Obtém detalhes de uma sala de voz
  Future<Map<String, dynamic>?> getVoiceRoomDetails(String roomId) async {
    try {
      final snapshot = await _voiceRoomsRef.child(roomId).once();
      if (snapshot.snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.snapshot.value as Map);
      }
      return null;
    } catch (e, stackTrace) {
      Logger.error('Error getting voice room details', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Escuta mudanças nas salas de voz ativas
  Stream<DatabaseEvent> listenToActiveVoiceRooms({
    required String roomType,
    String? clanId,
    String? federationId,
  }) {
    Query query = _voiceRoomsRef.orderByChild('isActive').equalTo(true);

    if (roomType == 'clan' && clanId != null) {
      query = query.orderByChild('clanId').equalTo(clanId);
    } else if (roomType == 'federation' && federationId != null) {
      query = query.orderByChild('federationId').equalTo(federationId);
    } else if (roomType == 'admin') {
      query = query.orderByChild('roomType').equalTo('admin');
    } else if (roomType == 'global') {
      query = query.orderByChild('roomType').equalTo('global');
    }

    return query.onValue;
  }

  /// Escuta participantes de uma sala de voz
  Stream<DatabaseEvent> listenToVoiceRoomParticipants(String roomId) {
    return _voiceRoomsRef.child(roomId).child('participants').onValue;
  }

  /// Envia mensagem para uma sala de chat (exemplo)
  Future<void> sendMessageToRoom(String roomId, String userId, String messageContent) async {
    try {
      final messagesRef = FirebaseDatabase.instance.ref('chat_rooms').child(roomId).child('messages');
      await messagesRef.push().set({
        'senderId': userId,
        'message': messageContent,
        'timestamp': ServerValue.timestamp,
      });
      Logger.info('Message sent to room $roomId by $userId');
    } catch (e, stackTrace) {
      Logger.error('Error sending message to room', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Escuta mensagens de uma sala de chat (exemplo)
  Stream<DatabaseEvent> listenToRoomMessages(String roomId) {
    return FirebaseDatabase.instance.ref('chat_rooms').child(roomId).child('messages').onValue;
  }

  /// Carrega as configurações do usuário
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    _notificationTypes.forEach((key, value) {
      _notificationTypes[key] = prefs.getBool('notificationType_$key') ?? true;
    });
    notifyListeners();
  }

  /// Salva as configurações do usuário
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
    for (final entry in _notificationTypes.entries) {
      await prefs.setBool('notificationType_${entry.key}', entry.value);
    }
    notifyListeners();
  }
}


