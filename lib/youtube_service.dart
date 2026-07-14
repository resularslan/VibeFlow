import 'package:ytmusicapi_dart/enums.dart' as yt_enums; 
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeMusicService {
  YTMusic? _ytMusic;
  final YoutubeExplode _ytExplode = YoutubeExplode();

  Future<YTMusic> get _musicClient async {
    _ytMusic ??= await YTMusic.create();
    return _ytMusic!;
  }

  // 🔥 isMusicMode parametresi ile hangi servisin kullanılacağını seçiyoruz
  Future<List<Map<dynamic, dynamic>>> searchMusic(String query, {bool isMusicMode = true}) async {
    try {
      if (isMusicMode) {
        // --- 1. SEÇENEK: SADECE YOUTUBE MUSIC ---
        final client = await _musicClient;
        final results = await client.search(query, filter: yt_enums.SearchFilter.songs);
        
        return results.map((item) {
          String artistName = 'Bilinmeyen Sanatçı';
          if (item['artists'] != null && item['artists'] is List && item['artists'].isNotEmpty) {
            artistName = item['artists'][0]['name'] ?? 'Bilinmeyen Sanatçı';
          }
          String thumbnailUrl = 'https://via.placeholder.com/150';
          if (item['thumbnails'] != null && item['thumbnails'] is List && item['thumbnails'].isNotEmpty) {
            thumbnailUrl = item['thumbnails'].last['url'] ?? thumbnailUrl;
          }
          return {
            'id': item['videoId'] ?? '',
            'title': item['title'] ?? 'İsimsiz Şarkı',
            'author': artistName,
            'thumbnail': thumbnailUrl,
            'path': ''
          };
        }).toList();
      } else {
        // --- 2. SEÇENEK: GENEL YOUTUBE (Vlog, Oyun, Slowed Reverb vs.) ---
        final results = await _ytExplode.search.search(query);
        
        return results.map((video) {
          return {
            'id': video.id.value,
            'title': video.title,
            'author': video.author,
            'thumbnail': video.thumbnails.highResUrl, // En yüksek kalite
            'path': '' 
          };
        }).toList();
      }
    } catch (e) {
      throw Exception("Arama sırasında hata: $e");
    }
  }

  Future<AudioOnlyStreamInfo> getAudioStream(String videoId) async {
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(
          videoId, ytClients: [YoutubeApiClient.androidVr]);
      return manifest.audioOnly.withHighestBitrate();
    } catch (e) {
      throw Exception("Ses akışı çıkarılamadı: $e");
    }
  }

  Future<Stream> getStream(String videoId) async {
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(
          videoId, ytClients: [YoutubeApiClient.androidVr]);
      final streamInfo = manifest.audioOnly.withHighestBitrate();
      return _ytExplode.videos.streamsClient.get(streamInfo);
    } catch (e) {
      throw Exception("Ses akışı çıkarılamadı: $e");
    }
  }

  void dispose() {
    _ytExplode.close();
    _ytMusic?.close();
  }
}