import 'package:ytmusicapi_dart/enums.dart' as yt_enums; 
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeMusicService {
  YTMusic? _ytMusic; // Nullable olarak tanımlıyoruz, başta boş.
  final YoutubeExplode _ytExplode = YoutubeExplode();

  // 🔥 SİHİR BURADA: Client sadece ilk çağrıldığında yaratılır, sonra hep aynı nesne döner.
  Future<YTMusic> get _musicClient async {
    _ytMusic ??= await YTMusic.create();
    return _ytMusic!;
  }

  Future<List<Map<String, dynamic>>> searchMusic(String query) async {
    try {
      final client = await _musicClient;
      final results = await client.search(query, filter: yt_enums.SearchFilter.songs);
      
      return results.map((item) {
        
        // 1. Sanatçı adını güvenli şekilde çıkar (artists listesinden)
        String artistName = 'Bilinmeyen Sanatçı';
        if (item['artists'] != null && item['artists'] is List && item['artists'].isNotEmpty) {
          // Listenin ilk elemanının 'name' değerini al, null ise varsayılana dön
          artistName = item['artists'][0]['name'] ?? 'Bilinmeyen Sanatçı';
        }

        // 2. Kapak fotoğrafını güvenli şekilde çıkar
        String thumbnailUrl = 'https://via.placeholder.com/150'; // Boş kalırsa çökmesin diye yedek
        if (item['thumbnails'] != null && item['thumbnails'] is List && item['thumbnails'].isNotEmpty) {
          // En yüksek kaliteli (genelde listedeki sonuncu) resmi al
          thumbnailUrl = item['thumbnails'].last['url'] ?? thumbnailUrl;
        }

        return {
          'id': item['videoId'] ?? '',
          'title': item['title'] ?? 'İsimsiz Şarkı', // 'name' DEĞİL, 'title' kullanıyoruz!
          'author': artistName,
          'thumbnail': thumbnailUrl,
          'path': '' // İndirme aşaması için boş path
        };
      }).toList();
      
    } catch (e) {
      throw Exception("Arama sırasında InnerTube API hatası: $e");
    }
  }

  Future<AudioOnlyStreamInfo> getAudioStream(String videoId) async {
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.androidVr,
          ],
        );
      final audioInfo = manifest.audioOnly.withHighestBitrate();
      return audioInfo;
    } catch (e) {
      throw Exception("Ses akışı çıkarılamadı: $e");
    }
  }

  Future<Stream> getStream(String videoId) async {
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.androidVr,
          ],
        );
      final streamInfo = manifest.audioOnly.withHighestBitrate();
      final stream = _ytExplode.videos.streamsClient.get(streamInfo);
      return stream;
    } catch (e) {
      throw Exception("Ses akışı çıkarılamadı: $e");
    }
  }

  
  void dispose() {
    // Kapatma işlemi her aramada değil, SADECE UYGULAMA KAPANIRKEN burada yapılır!
    _ytExplode.close();
    _ytMusic?.close();
  }
}