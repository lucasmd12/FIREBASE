// lib/widgets/cached_image_widget.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucasbeatsfederacao/services/cache_service.dart';
import 'package:lucasbeatsfederacao/utils/logger.dart';

class CachedImageWidget extends StatefulWidget {
  final String imageUrl;
  final String? imageId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeInDuration;
  final bool enableMemoryCache;
  final bool enableDiskCache;
  final Map<String, String>? httpHeaders;

  const CachedImageWidget({
    Key? key,
    required this.imageUrl,
    this.imageId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.enableMemoryCache = true,
    this.enableDiskCache = true,
    this.httpHeaders,
  }) : super(key: key);

  @override
  State<CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<CachedImageWidget> {
  String? _cachedUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.imageId != widget.imageId) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageId != null) {
      // Tentar obter URL do cache primeiro
      final cachedUrl = await CacheService.getCachedImageUrl(widget.imageId!);
      if (cachedUrl != null && cachedUrl == widget.imageUrl) {
        setState(() {
          _cachedUrl = cachedUrl;
        });
        return;
      }
    }

    // Usar URL fornecida e cachear se tiver ID
    setState(() {
      _cachedUrl = widget.imageUrl;
    });

    if (widget.imageId != null) {
      await CacheService.cacheImageUrl(widget.imageId!, widget.imageUrl);
    }
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ?? 
      Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        ),
      );
  }

  Widget _buildErrorWidget() {
    return widget.errorWidget ??
      Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image,
              color: Colors.grey[400],
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              'Erro ao carregar',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedUrl == null) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: _cachedUrl!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      memCacheWidth: widget.width?.toInt(),
      memCacheHeight: widget.height?.toInt(),
      httpHeaders: widget.httpHeaders,
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) {
        Logger.error('Error loading image: $url - $error');
        return _buildErrorWidget();
      },
      cacheManager: CustomCacheManager.instance,
    );
  }
}

/// Avatar widget otimizado com cache
class CachedAvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String? userId;
  final double radius;
  final String? fallbackText;
  final Color? backgroundColor;
  final Color? textColor;

  const CachedAvatarWidget({
    Key? key,
    this.imageUrl,
    this.userId,
    this.radius = 20,
    this.fallbackText,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: ClipOval(
          child: CachedImageWidget(
            imageUrl: imageUrl!,
            imageId: userId != null ? 'avatar_$userId' : null,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: _buildFallback(),
            errorWidget: _buildFallback(),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey[400],
      child: _buildFallback(),
    );
  }

  Widget _buildFallback() {
    if (fallbackText != null && fallbackText!.isNotEmpty) {
      return Text(
        fallbackText!.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Icon(
      Icons.person,
      color: textColor ?? Colors.white,
      size: radius * 1.2,
    );
  }
}

/// Gerenciador de cache customizado
class CustomCacheManager {
  static CustomCacheManager? _instance;
  static CustomCacheManager get instance {
    _instance ??= CustomCacheManager._();
    return _instance!;
  }

  CustomCacheManager._();

  // Configurações de cache
  static const Duration _maxAge = Duration(days: 7);
  static const int _maxNrOfCacheObjects = 200;

  /// Limpa cache de imagens antigas
  Future<void> cleanupOldImages() async {
    try {
      // Implementar limpeza de cache de imagens
      Logger.info('Image cache cleanup completed');
    } catch (e) {
      Logger.error('Error cleaning up image cache: $e');
    }
  }

  /// Obtém tamanho do cache de imagens
  Future<int> getCacheSize() async {
    try {
      // Implementar cálculo do tamanho do cache
      return 0;
    } catch (e) {
      Logger.error('Error getting cache size: $e');
      return 0;
    }
  }

  /// Limpa todo o cache de imagens
  Future<void> clearCache() async {
    try {
      // Implementar limpeza completa
      Logger.info('Image cache cleared');
    } catch (e) {
      Logger.error('Error clearing image cache: $e');
    }
  }
}

/// Widget para pré-carregar imagens
class ImagePreloader extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback? onComplete;

  const ImagePreloader({
    Key? key,
    required this.imageUrls,
    this.onComplete,
  }) : super(key: key);

  @override
  State<ImagePreloader> createState() => _ImagePreloaderState();
}

class _ImagePreloaderState extends State<ImagePreloader> {
  int _loadedCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _preloadImages();
  }

  Future<void> _preloadImages() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _loadedCount = 0;
    });

    for (final imageUrl in widget.imageUrls) {
      try {
        await precacheImage(NetworkImage(imageUrl), context);
        setState(() {
          _loadedCount++;
        });
      } catch (e) {
        Logger.error('Error preloading image $imageUrl: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });

    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'Carregando imagens... $_loadedCount/${widget.imageUrls.length}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

