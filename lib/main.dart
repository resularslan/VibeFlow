import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:namer_app/youtube_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'VibeFlow',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  await Hive.initFlutter();
  await Hive.openBox('libraryBox');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'VibeFlow',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1DB954),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  final _libraryBox = Hive.box('libraryBox');
  final YouTubeMusicService _musicService = YouTubeMusicService();

  String _language = 'tr';
  String get language => _language;
  String t(String key) => AppTranslations.get(_language, key);

  Map<dynamic, dynamic> _playlists = {};
  List<Map<dynamic, dynamic>> _downloadedSongs = [];
  List<Map<dynamic, dynamic>> _recentSongs = [];

  Map<dynamic, dynamic> get playlists => _playlists;
  List<Map<dynamic, dynamic>> get downloadedSongs => _downloadedSongs;
  List<Map<dynamic, dynamic>> get recentSongs => _recentSongs;

  bool _isSearching = false;
  bool _isAudioLoading = false;
  String? _downloadingSongId;

  bool get isSearching => _isSearching;
  bool get isAudioLoading => _isAudioLoading;
  String? get downloadingSongId => _downloadingSongId;

  List<dynamic> _searchResults = [];
  List<dynamic> get searchResults => _searchResults;

  final AudioPlayer _audioPlayer = AudioPlayer();
  AudioPlayer get player => _audioPlayer;

  List<Map<dynamic, dynamic>> _queue = [];
  int _queueIndex = 0;
  bool _isPlaying = false;
  
  
  bool _isShuffle = false;
  bool _isRepeat = false;

  bool _isPlaylistDownloading = false;
  bool _cancelPlaylistDownload = false;
  
  bool get isPlaylistDownloading => _isPlaylistDownloading;

  void cancelDownload() {
    _cancelPlaylistDownload = true;
    notifyListeners();
  }
  
  Map<dynamic, dynamic>? _currentSong;
  List<int> _shuffledIndices = [];
  int _shuffledPointer = 0;

  String? _currentPlaylistName;

  String? _prefetchedSongId;
  AudioSource? _prefetchedNextSource;

  bool get isPlaying => _isPlaying;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _isRepeat;
  Map<dynamic, dynamic>? get currentSong => _currentSong;

  MyAppState() {
    _initAudio();
    _loadData();
  }

  void _loadData() {
    _language = _libraryBox.get('language', defaultValue: 'tr');
    _playlists = Map<dynamic, dynamic>.from(_libraryBox.get('custom_playlists', defaultValue: {}));
    _downloadedSongs = List<Map<dynamic, dynamic>>.from(_libraryBox.get('downloaded_songs', defaultValue: []));
    _recentSongs = List<Map<dynamic, dynamic>>.from(_libraryBox.get('recent_songs', defaultValue: []));
    notifyListeners();
  }

  // 🔥 Seçili dili ayarlayan yeni fonksiyon
  void setLanguage(String lang) {
    if (_language != lang) {
      _language = lang;
      _libraryBox.put('language', _language);
      notifyListeners();
    }
  }

  void createPlaylist(String name) {
    if (name.isNotEmpty && !_playlists.containsKey(name)) {
      _playlists[name] = [];
      _libraryBox.put('custom_playlists', _playlists);
      notifyListeners();
    }
  }

  void addSongToPlaylist(String playlistName, Map<dynamic, dynamic> songToAdd) {
    if (_playlists.containsKey(playlistName)) {
      List songs = _playlists[playlistName];
      if (!songs.any((s) => s['id'] == songToAdd['id'])) {
        songs.add(songToAdd);
        _libraryBox.put('custom_playlists', _playlists);
        
        if (_currentPlaylistName == playlistName) {
          _queue.add(songToAdd);
          if (_isShuffle) {
            _shuffledIndices.add(_queue.length - 1);
          }
          _preloadNextSong();
        }
        notifyListeners();
      }
    }
  }

  void removeSongFromPlaylist(String playlistName, String songId) {
    if (_playlists.containsKey(playlistName)) {
      List songs = _playlists[playlistName];
      songs.removeWhere((s) => s['id'] == songId);
      _libraryBox.put('custom_playlists', _playlists);
      notifyListeners();
    }
  }

  void deletePlaylist(String playlistName) {
    _playlists.remove(playlistName);
    _libraryBox.put('custom_playlists', _playlists);
    if (_currentPlaylistName == playlistName) {
      _currentPlaylistName = null;
    }
    notifyListeners();
  }

  void reorderPlaylist(String playlistName, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    List currentList = List.from(_playlists[playlistName]);
    final item = currentList.removeAt(oldIndex);
    currentList.insert(newIndex, item);
    _playlists[playlistName] = currentList;
    _libraryBox.put('custom_playlists', _playlists);
    notifyListeners();
  }

  void reorderDownloadedSongs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    List<Map<dynamic, dynamic>> currentList = List.from(_downloadedSongs);
    final item = currentList.removeAt(oldIndex);
    currentList.insert(newIndex, item);
    _downloadedSongs = currentList;
    _libraryBox.put('downloaded_songs', _downloadedSongs);
    notifyListeners();
  }

  void addToRecents(Map<dynamic, dynamic> song) {
    _recentSongs.removeWhere((s) => s['id'] == song['id']);
    _recentSongs.insert(0, song);
    if (_recentSongs.length > 10) _recentSongs.removeLast();
    _libraryBox.put('recent_songs', _recentSongs);
    notifyListeners();
  }

  void removeFromRecents(String songId) {
    _recentSongs.removeWhere((s) => s['id'] == songId);
    _libraryBox.put('recent_songs', _recentSongs);
    notifyListeners();
  }

  Future<void> performSearch(String query) async {
    if (query.isEmpty) return;
    _isSearching = true;
    notifyListeners();

    try {
      _searchResults = await _musicService.searchMusic(query);
    } catch (e) {
      debugPrint("❌ Arama Hatası: $e");
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  Future<void> _initAudio() async {
    _audioPlayer.playerStateStream.listen((playerState) {
      _isPlaying = playerState.playing;
      if (playerState.processingState == ProcessingState.completed) {
        playNext();
      }
      notifyListeners();
    });
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.isNotEmpty) {
      _shuffledIndices = List.generate(_queue.length, (i) => i)..shuffle();
      int currentInQueue = _queueIndex;
      if (_queue.length > 1) {
        _shuffledIndices.remove(currentInQueue);
        _shuffledIndices.insert(0, currentInQueue);
      }
      _shuffledPointer = 0;
    }
    _preloadNextSong(); 
    notifyListeners();
  }

  void toggleRepeat() {
    _isRepeat = !_isRepeat;
    _preloadNextSong(); 
    notifyListeners();
  }

  void playSingleSong(dynamic video, {BuildContext? context}) {
    // 🔥 KORUMA 1: Eğer tıklanan şarkı zaten şu an çalan şarkıysa, API isteği atma!
    if (_currentSong != null && _currentSong!['id'] == video['id']) {
      // Sadece Player ekranını aç ve işlemi kes
      if (context != null && context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const PlayerScreen()));
      }
      return; 
    }

    final mapVideo = {
      'id': video['id'],
      'title': video['title'],
      'author': video['author'],
      'thumbnail': video['thumbnail'],
      'path': video['path'] ?? ''
    };
    _queue = [mapVideo];
    _queueIndex = 0;
    _currentPlaylistName = null; 
    _playCurrentQueueItem(context: context);
  }

  void playPlaylist(List songs, {BuildContext? context, int? startIndex, String? playlistName}) {
    if (songs.isEmpty) return;

    int targetIndex = startIndex ?? 0;
    var targetSong = songs[targetIndex];

    // 🔥 KORUMA 2: Eğer tıklanan şarkı zaten çalansa ve aynı listedeysek, API isteği atma!
    if (_currentSong != null && _currentSong!['id'] == targetSong['id'] && _currentPlaylistName == playlistName) {
      if (context != null && context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const PlayerScreen()));
      }
      return;
    }

    _currentPlaylistName = playlistName; 
    _queue = List<Map<dynamic, dynamic>>.from(songs);

    if (_isShuffle) {
      _shuffledIndices = List.generate(_queue.length, (i) => i)..shuffle();
      if (startIndex != null) {
        _shuffledIndices.remove(startIndex);
        _shuffledIndices.insert(0, startIndex);
      }
      _shuffledPointer = 0;
      _queueIndex = _shuffledIndices[_shuffledPointer];
    } else {
      _queueIndex = startIndex ?? 0;
    }
    _playCurrentQueueItem(context: context);
  }

  void playNext({BuildContext? context}) {
    if (_queue.isEmpty) return;

    if (_isShuffle) {
      _shuffledPointer++;
      if (_shuffledPointer >= _shuffledIndices.length) {
        if (_isRepeat) {
          int lastPlayedIndex = _shuffledIndices.last;
          _shuffledIndices.shuffle();
          if (_shuffledIndices.length > 1 && _shuffledIndices.first == lastPlayedIndex) {
            int temp = _shuffledIndices[0];
            _shuffledIndices[0] = _shuffledIndices.last;
            _shuffledIndices.last = temp;
          }
          _shuffledPointer = 0;
          _queueIndex = _shuffledIndices[_shuffledPointer];
        } else {
          _audioPlayer.stop();
          _isPlaying = false;
          notifyListeners();
          return;
        }
      } else {
        _queueIndex = _shuffledIndices[_shuffledPointer];
      }
    } else {
      _queueIndex++;
      if (_queueIndex >= _queue.length) {
        if (_isRepeat) {
          _queueIndex = 0; 
        } else {
          _audioPlayer.stop();
          _isPlaying = false;
          notifyListeners();
          return;
        }
      }
    }
    _playCurrentQueueItem(context: context);
  }

  void playPrevious({BuildContext? context}) {
    if (_queue.isEmpty) return;
    if (_isShuffle) {
      _shuffledPointer--;
      if (_shuffledPointer < 0) _shuffledPointer = _shuffledIndices.length - 1;
      _queueIndex = _shuffledIndices[_shuffledPointer];
    } else {
      _queueIndex--;
      if (_queueIndex < 0) _queueIndex = 0;
    }
    _playCurrentQueueItem(context: context);
  }

  Future<void> _preloadNextSong() async {
    if (_queue.isEmpty) return;

    int nextIndex;
    if (_isShuffle) {
      int tempPointer = _shuffledPointer + 1;
      if (tempPointer >= _shuffledIndices.length) {
        if (_isRepeat) {
          nextIndex = _shuffledIndices[0]; 
        } else {
          return; 
        }
      } else {
        nextIndex = _shuffledIndices[tempPointer];
      }
    } else {
      nextIndex = _queueIndex + 1;
      if (nextIndex >= _queue.length) {
        if (_isRepeat) {
          nextIndex = 0;
        } else {
          return; 
        }
      }
    }

    var nextSong = _queue[nextIndex];
    String nextId = nextSong['id'];

    var dlMatch = _downloadedSongs.firstWhere((s) => s['id'] == nextId, orElse: () => {});
    
    final nextMediaItem = MediaItem(
      id: nextSong['id'],
      album: "VibeFlow",
      title: nextSong['title'],
      artist: nextSong['author'],
      artUri: Uri.parse(nextSong['thumbnail']),
    );

    if (dlMatch.isNotEmpty) {
      _prefetchedSongId = nextId;
      _prefetchedNextSource = AudioSource.file(dlMatch['path'], tag: nextMediaItem);
      return;
    }

    try {
      var audioStreamInfo = await _musicService.getAudioStream(nextId);
      _prefetchedNextSource = AudioSource.uri(
        Uri.parse(audioStreamInfo.url.toString()), 
        tag: nextMediaItem
      );
      _prefetchedSongId = nextId;
    } catch (e) {
      _prefetchedSongId = null;
      _prefetchedNextSource = null;
    }
  }

  Future<void> _playCurrentQueueItem({BuildContext? context}) async {
    if (_queue.isEmpty || _queueIndex >= _queue.length) return;

    var song = _queue[_queueIndex];
    _currentSong = song;
    _isAudioLoading = true;
    notifyListeners();

    final mediaItem = MediaItem(
      id: song['id'],
      album: "VibeFlow",
      title: song['title'],
      artist: song['author'],
      artUri: Uri.parse(song['thumbnail']),
    );

    try {
      AudioSource? sourceToPlay;
      var dlMatch = _downloadedSongs.firstWhere((s) => s['id'] == song['id'], orElse: () => {});

      if (dlMatch.isNotEmpty) {
        File file = File(dlMatch['path']);
        if (await file.exists()) {
          sourceToPlay = AudioSource.file(dlMatch['path'], tag: mediaItem);
        } else {
          throw Exception(t('file_corrupted'));
        }
      } 
      else if (_prefetchedSongId == song['id'] && _prefetchedNextSource != null) {
        sourceToPlay = _prefetchedNextSource;
      } 
      else {
        var audioStreamInfo = await _musicService.getAudioStream(song['id']);
        sourceToPlay = AudioSource.uri(
          Uri.parse(audioStreamInfo.url.toString()), 
          tag: mediaItem
        );
      }

      await _audioPlayer.setAudioSource(sourceToPlay!);
      _audioPlayer.play();
      _preloadNextSong();

    } catch (e) {
      debugPrint("Çalma Hatası: $e");
      final localContext = context;
      if (localContext != null && localContext.mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(content: Text("${song['title']} ${t('skipped_error')}"), duration: const Duration(seconds: 1)),
        );
      }
      playNext(context: context);
      return;
    } finally {
      _isAudioLoading = false;
      notifyListeners();
    }
  }

  void seekAudio(Duration position) => _audioPlayer.seek(position);
  void setVolume(double volume) => _audioPlayer.setVolume(volume);
  void togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  Future<void> downloadSpecificSong(Map<dynamic, dynamic> songToDownload, BuildContext context) async {
    final targetId = songToDownload['id'];
    if (_downloadedSongs.any((s) => s['id'] == targetId) || _downloadingSongId != null) return;

    _downloadingSongId = targetId;
    notifyListeners();

    File? file;
    IOSink? fileStream;
    try {
      var stream = await _musicService.getStream(targetId);
      var tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/$targetId.m4a';
      file = File(filePath);
      
      fileStream = file.openWrite();
      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      final savedSong = Map<dynamic, dynamic>.from(songToDownload);
      savedSong['path'] = filePath;
      _downloadedSongs.add(savedSong);
      _libraryBox.put('downloaded_songs', _downloadedSongs);
      
      if (_currentPlaylistName == "downloaded_songs") {
        _queue.add(savedSong);
        if (_isShuffle) _shuffledIndices.add(_queue.length - 1);
        _preloadNextSong();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('song_downloaded')), backgroundColor: const Color(0xFF1DB954)),
      );
    } catch (e) {
      debugPrint("İndirme Hatası: $e");
      if (fileStream != null) await fileStream.close();
      if (file != null && await file.exists()) await file.delete();
    } finally {
      if (_downloadingSongId == targetId) _downloadingSongId = null;
      notifyListeners();
    }
  }

  Future<void> downloadAllFromPlaylist(String playlistName, BuildContext context) async {
    List songs = _playlists[playlistName] ?? [];
    // Eğer liste boşsa veya zaten bir indirme işlemi devam ediyorsa hiçbir şey yapma (Spam koruması)
    if (songs.isEmpty || _isPlaylistDownloading) return; 
    
    _isPlaylistDownloading = true;
    _cancelPlaylistDownload = false;
    notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('playlist_download_started')), backgroundColor: const Color(0xFF1DB954)),
    );

    for (var song in songs) {
      // 🔥 KULLANICI İPTAL ETTİ Mİ KONTROLÜ
      if (_cancelPlaylistDownload) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("İndirme işlemi iptal edildi."), backgroundColor: Colors.orange),
          );
        }
        break; // Döngüyü kır ve işlemi durdur
      }

      if (!_downloadedSongs.any((s) => s['id'] == song['id'])) {
        await downloadSpecificSong(song, context);
        await Future.delayed(const Duration(milliseconds: 1500)); // İnsani mola
      }
    }

    // İşlem bittiğinde veya iptal edildiğinde durumları sıfırla
    _isPlaylistDownloading = false;
    _cancelPlaylistDownload = false;
    notifyListeners();
  }

  Future<void> deleteDownloadedSong(String songId) async {
    final songIndex = _downloadedSongs.indexWhere((s) => s['id'] == songId);
    if (songIndex != -1) {
      try {
        final file = File(_downloadedSongs[songIndex]['path']);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _downloadedSongs.removeAt(songIndex);
      _libraryBox.put('downloaded_songs', _downloadedSongs);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _musicService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

// =========================================================================
// UI WIDGETS VE TRANSLATIONS (ÇEVİRİLER)
// =========================================================================

class AppTranslations {
  static const Map<String, Map<String, String>> keys = {
    'tr': {
      'welcome': 'Hoş Geldin',
      'home_quiet': 'Henüz buralar çok sessiz.',
      'home_create_first': 'Kütüphaneden ilk çalma listeni oluşturarak başlayabilirsin.',
      'your_playlists': 'Senin Listelerin',
      'search_title': 'Arama',
      'search_hint': 'Ne dinlemek istiyorsun?',
      'recent_songs': 'Son Çalınanlar',
      'search_empty': 'Aramak istediğiniz şarkıyı yazın.',
      'your_library': 'Kütüphanen',
      'create_new_playlist': 'Yeni Çalma Listesi Oluştur',
      'downloaded_songs': 'İndirilen Şarkılar',
      'songs_offline_ready': 'şarkı • Çevrimdışı hazır',
      'songs_count': 'Şarkı',
      'play': 'Oynat',
      'download_all': 'Tümünü İndir',
      'delete': 'Sil',
      'delete_playlist': 'Sil',
      'playlist_empty': 'Bu liste boş.',
      'now_playing': 'Şimdi Çalıyor',
      'no_song': 'Şarkı Yok',
      'no_song_selected': 'Henüz Şarkı Seçilmedi',
      'connecting': 'Bağlanıyor...',
      'saved_on_device': 'Cihazda Kayıtlı',
      'online_stream': 'Çevrimiçi Akış',
      'add_to_playlist': 'Çalma Listesine Ekle',
      'create_playlist_first': 'Önce Kütüphane\'den bir liste oluşturun.',
      'new_playlist': 'Yeni Çalma Listesi',
      'cancel': 'İptal',
      'create': 'Oluştur',
      'home_tab': 'Anasayfa',
      'search_tab': 'Ara',
      'library_tab': 'Kütüphane',
      'song_downloaded': 'Şarkı başarıyla indirildi!',
      'playlist_download_started': 'Liste indirmesi başlatıldı...',
      'added_to_playlist': 'listesine eklendi!',
      'skipped_error': 'atlandı (Hata: Bağlantı)',
      'no_downloaded_songs': 'Henüz indirilen şarkı yok.',
      'file_corrupted': 'Dosya bozuk.',
      'language_select': 'Dil',
      'cancel_download': 'İptal Et',
    },
    'en': {
      'welcome': 'Welcome',
      'home_quiet': 'It\'s quiet here.',
      'home_create_first': 'Start by creating your first playlist from the library.',
      'your_playlists': 'Your Playlists',
      'search_title': 'Search',
      'search_hint': 'What do you want to listen to?',
      'recent_songs': 'Recently Played',
      'search_empty': 'Type the song you want to search.',
      'your_library': 'Your Library',
      'create_new_playlist': 'Create New Playlist',
      'downloaded_songs': 'Downloaded Songs',
      'songs_offline_ready': 'songs • Ready offline',
      'songs_count': 'Songs',
      'play': 'Play',
      'download_all': 'Download All',
      'delete': 'Delete',
      'delete_playlist': 'Delete',
      'playlist_empty': 'This playlist is empty.',
      'now_playing': 'Now Playing',
      'no_song': 'No Song',
      'no_song_selected': 'No Song Selected',
      'connecting': 'Connecting...',
      'saved_on_device': 'Saved on Device',
      'online_stream': 'Online Stream',
      'add_to_playlist': 'Add to Playlist',
      'create_playlist_first': 'Create a playlist from the Library first.',
      'new_playlist': 'New Playlist',
      'cancel': 'Cancel',
      'create': 'Create',
      'home_tab': 'Home',
      'search_tab': 'Search',
      'library_tab': 'Library',
      'song_downloaded': 'Song downloaded successfully!',
      'playlist_download_started': 'Playlist download started...',
      'added_to_playlist': 'added to playlist!',
      'skipped_error': 'skipped (Error: Connection)',
      'no_downloaded_songs': 'No downloaded songs yet.',
      'file_corrupted': 'File is corrupted.',
      'language_select': 'Language',
      'cancel_download': 'Cancel',
    }
  };

  static String get(String lang, String key) {
    return keys[lang]?[key] ?? key;
  }
}

void showPlaylistSelectionSheet(BuildContext context, MyAppState appState, Map<dynamic, dynamic> songToSave) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    isScrollControlled: true, 
    useSafeArea: true, 
    builder: (context) {
      return SafeArea( 
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(appState.t('add_to_playlist'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (appState.playlists.isEmpty)
                Padding(padding: const EdgeInsets.all(16.0), child: Text(appState.t('create_playlist_first'), style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center))
              else
                ...appState.playlists.keys.map((playlistName) {
                  return ListTile(
                    leading: const Icon(Icons.queue_music, color: Colors.white),
                    title: Text(playlistName, style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      appState.addSongToPlaylist(playlistName, songToSave);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$playlistName' ${appState.t('added_to_playlist')}"), backgroundColor: const Color(0xFF1DB954)));
                    },
                  );
                }),
            ],
          ),
        ),
      );
    },
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const SearchPage();
        break;
      case 2:
        page = const LibraryPage();
        break;
      default:
        throw UnimplementedError('Hatalı sayfa');
    }
    return Scaffold(
      body: Column(children: [Expanded(child: page), const MiniPlayer()]),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            selectedIndex = index;
          });
        },
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFF1DB954).withValues(alpha: 0.3),
        selectedIndex: selectedIndex,
        destinations: <Widget>[
          NavigationDestination(selectedIcon: const Icon(Icons.home, color: Colors.white), icon: const Icon(Icons.home_outlined, color: Colors.grey), label: appState.t('home_tab')),
          NavigationDestination(selectedIcon: const Icon(Icons.search, color: Colors.white), icon: const Icon(Icons.search_outlined, color: Colors.grey), label: appState.t('search_tab')),
          NavigationDestination(selectedIcon: const Icon(Icons.library_music, color: Colors.white), icon: const Icon(Icons.library_music_outlined, color: Colors.grey), label: appState.t('library_tab'))
        ],
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final song = appState.currentSong;
    final hasSong = song != null;
    
    final isDownloaded = hasSong && appState.downloadedSongs.any((s) => s['id'] == song['id']);
    final isDownloading = hasSong && appState.downloadingSongId == song['id'];

    return Container(
      height: 64,
      decoration: const BoxDecoration(color: Color(0xFF181818), border: Border(bottom: BorderSide(color: Colors.black, width: 1))),
      child: Row(
        children: [
          Container(
            width: 64, height: 64, color: Colors.grey[850],
            child: hasSong 
                ? Image.network(song['thumbnail'] ?? '', fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, color: Colors.white, size: 32))
                : const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () { if (hasSong) Navigator.push(context, MaterialPageRoute(builder: (context) => const PlayerScreen())); },
              onLongPress: () { if (hasSong) showPlaylistSelectionSheet(context, appState, song); },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hasSong ? song['title'] : appState.t('no_song_selected'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(appState.isAudioLoading ? appState.t('connecting') : (isDownloaded ? appState.t('saved_on_device') : (hasSong ? appState.t('online_stream') : '')), style: const TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (isDownloading)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2)))
          else if (hasSong && !isDownloaded && !appState.isAudioLoading)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey, size: 28),
              onPressed: () => appState.downloadSpecificSong(song, context)
            )
          else if (isDownloaded)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 24)),

          IconButton(
            icon: Icon(appState.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
            onPressed: (hasSong && !appState.isAudioLoading) ? () => appState.togglePlay() : null
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appState.t('search_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: SearchBar(
                controller: _searchController,
                hintText: appState.t('search_hint'),
                hintStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(color: Colors.grey)),
                backgroundColor: WidgetStatePropertyAll<Color>(Colors.white.withValues(alpha: 0.1)),
                padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.symmetric(horizontal: 16.0)),
                leading: const Icon(Icons.search, color: Colors.grey),
                trailing: _searchController.text.isNotEmpty
                    ? [
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            appState.clearSearchResults();
                            setState(() {});
                          },
                        )
                      ]
                    : null,
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 500), () {
                    if (value.isNotEmpty) {
                      appState.performSearch(value);
                    } else {
                      appState.clearSearchResults();
                    }
                  });
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _searchController.text.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (appState.recentSongs.isNotEmpty) ...[
                          Text(appState.t('recent_songs'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: appState.recentSongs.length,
                              itemBuilder: (context, index) {
                                final video = appState.recentSongs[index];
                                final isDl = appState.downloadedSongs.any((s) => s['id'] == video['id']);
                                final isDling = appState.downloadingSongId == video['id'];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                                  leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(video['thumbnail'], width: 64, height: 48, fit: BoxFit.cover)),
                                  title: Text(video['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(video['author'], maxLines: 1),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.grey), onPressed: () => showPlaylistSelectionSheet(context, appState, video)),
                                      if (isDling)
                                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2))
                                      else if (isDl)
                                        const Icon(Icons.offline_pin, color: Color(0xFF1DB954))
                                      else
                                        IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey), onPressed: () => appState.downloadSpecificSong(video, context)),
                                      IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 20), onPressed: () => appState.removeFromRecents(video['id'])),
                                    ],
                                  ),
                                  onTap: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    appState.addToRecents(video);
                                    appState.playSingleSong(video, context: context);
                                  },
                                );
                              },
                            ),
                          ),
                        ] else
                          Center(child: Text(appState.t('search_empty'), style: TextStyle(color: Colors.grey[500], fontSize: 16))),
                      ],
                    )
                  : appState.isSearching
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
                      : ListView.builder(
                          itemCount: appState.searchResults.length,
                          itemBuilder: (context, index) {
                            final video = appState.searchResults[index];
                            final mapVideo = {
                              'id': video['id'],
                              'title': video['title'],
                              'author': video['author'],
                              'thumbnail': video['thumbnail'],
                              'path': ''
                            };
                            final isDl = appState.downloadedSongs.any((s) => s['id'] == mapVideo['id']);
                            final isDling = appState.downloadingSongId == mapVideo['id'];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(video['thumbnail'], width: 64, height: 48, fit: BoxFit.cover)),
                              title: Text(video['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(video['author'], maxLines: 1),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.grey), onPressed: () => showPlaylistSelectionSheet(context, appState, mapVideo)),
                                  if (isDling)
                                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2))
                                  else if (isDl)
                                    const Icon(Icons.offline_pin, color: Color(0xFF1DB954))
                                  else
                                    IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey), onPressed: () => appState.downloadSpecificSong(mapVideo, context)),
                                ],
                              ),
                              onTap: () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                appState.addToRecents(mapVideo);
                                appState.playSingleSong(mapVideo, context: context);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(appState.t('welcome'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                // 🔥 Yeni PopupMenuButton Tasarımı
                PopupMenuButton<String>(
                  initialValue: appState.language,
                  onSelected: (String result) {
                    appState.setLanguage(result);
                  },
                  color: Colors.grey[900],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(appState.t('language_select'), style: const TextStyle(color: Colors.white, fontSize: 16)),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'tr',
                      child: Text('Türkçe', style: TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem<String>(
                      value: 'en',
                      child: Text('English', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (appState.playlists.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    const Icon(Icons.queue_music, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(appState.t('home_quiet'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(appState.t('home_create_first'), style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center)
                  ],
                ),
              )
            else ...[
              Text(appState.t('your_playlists'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: appState.playlists.length,
                itemBuilder: (context, index) {
                  String playlistName = appState.playlists.keys.elementAt(index);
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailsPage(playlistName: playlistName))),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        children: [
                          Container(width: 56, color: Colors.grey[800], child: const Icon(Icons.music_note)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(playlistName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))
                        ],
                      ),
                    ),
                  );
                },
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class DownloadedSongsPage extends StatefulWidget {
  const DownloadedSongsPage({super.key});
  @override
  State<DownloadedSongsPage> createState() => _DownloadedSongsPageState();
}

class _DownloadedSongsPageState extends State<DownloadedSongsPage> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    List allSongs = appState.downloadedSongs;


    return Scaffold(
      appBar: AppBar(
        title: Text(appState.t('downloaded_songs')),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: Icon(_isEditing ? Icons.check : Icons.edit, color: const Color(0xFF1DB954)), onPressed: () => setState(() => _isEditing = !_isEditing))
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(appState.t('play')),
                    onPressed: allSongs.isEmpty ? null : () => appState.playPlaylist(allSongs, context: context, playlistName: "downloaded_songs"),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            Expanded(
              child: allSongs.isEmpty
                  ? Center(child: Text(appState.t('no_downloaded_songs'), style: TextStyle(color: Colors.grey[600])))
                  : _isEditing
                      ? ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.only(top: 8, left: 8, right: 8, bottom: MediaQuery.of(context).padding.bottom + 80),
                          itemCount: allSongs.length,
                          onReorder: (oldIndex, newIndex) => appState.reorderDownloadedSongs(oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final song = allSongs[index];
                            return ReorderableDragStartListener(
                              index: index,
                              key: ValueKey("dl_${song['id']}"),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () {
                                        appState.deleteDownloadedSong(song['id']);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 40, height: 40, fit: BoxFit.cover)),
                                  ],
                                ),
                                title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(song['author'], maxLines: 1),
                                trailing: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.drag_handle, color: Colors.grey, size: 28)),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(top: 8, left: 8, right: 8, bottom: MediaQuery.of(context).padding.bottom + 80),
                          itemCount: allSongs.length,
                          itemBuilder: (context, index) {
                            final song = allSongs[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                              title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(song['author'], maxLines: 1),
                              trailing: const Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 20),
                              onTap: () => appState.playPlaylist(allSongs, context: context, startIndex: index, playlistName: "downloaded_songs"),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Row(
            children: [
              const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)),
              const SizedBox(width: 16),
              Text(appState.t('your_library'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(width: 50, height: 50, color: Colors.grey[800], child: const Icon(Icons.add)),
            title: Text(appState.t('create_new_playlist')),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  final TextEditingController controller = TextEditingController();
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: Text(appState.t('new_playlist'), style: TextStyle(color: Colors.white)),
                    content: TextField(controller: controller, style: const TextStyle(color: Colors.white), autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Iptal', style: TextStyle(color: Colors.grey))),
                      TextButton(
                        onPressed: () {
                          appState.createPlaylist(controller.text);
                          Navigator.pop(context);
                        },
                        child: const Text('Oluştur', style: TextStyle(color: Color(0xFF1DB954))),
                      )
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(width: 50, height: 50, color: const Color(0xFF1DB954), child: const Icon(Icons.download_done, color: Colors.white)),
            title: Text(appState.t('downloaded_songs')),
            subtitle: Text('${appState.downloadedSongs.length} ${appState.t('songs_offline_ready')}'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadedSongsPage()));
            },
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.black),
          const SizedBox(height: 16),
          ...appState.playlists.entries.map((entry) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 50, height: 50, color: Colors.grey[850], child: const Icon(Icons.queue_music, color: Colors.white)),
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${entry.value.length} ${appState.t('songs_count')}'),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailsPage(playlistName: entry.key)));
              },
            );
          }),
        ],
      ),
    );
  }
}

class PlaylistDetailsPage extends StatefulWidget {
  final String playlistName;
  const PlaylistDetailsPage({super.key, required this.playlistName});
  @override
  State<PlaylistDetailsPage> createState() => _PlaylistDetailsPageState();
}

class _PlaylistDetailsPageState extends State<PlaylistDetailsPage> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    List allSongs = appState.playlists[widget.playlistName] ?? [];
    // 🔥 Bütün şarkıların indirilip indirilmediğini kontrol eden mantık
    bool isAllDownloaded = allSongs.isNotEmpty && allSongs.every((song) => 
        appState.downloadedSongs.any((s) => s['id'] == song['id'])
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: Icon(_isEditing ? Icons.check : Icons.edit, color: const Color(0xFF1DB954)), onPressed: () => setState(() => _isEditing = !_isEditing))
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(appState.t('play')),
                      onPressed: allSongs.isEmpty ? null : () => appState.playPlaylist(allSongs, context: context, playlistName: widget.playlistName),
                    ),
                    const SizedBox(width: 8),
                    appState.isPlaylistDownloading
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                            icon: const Icon(Icons.cancel),
                            label: Text(appState.t('cancel_download')),
                            onPressed: () => appState.cancelDownload(),
                          )
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800], 
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white.withValues(alpha: 0.05), // Gölgeli arka plan
                              disabledForegroundColor: Colors.grey[600], // Gölgeli yazı ve ikon
                            ),
                            icon: const Icon(Icons.download),
                            label: Text(appState.t('download_all')),
                            // 🔥 Eğer liste boşsa veya hepsi indirilmişse butonu pasif (null) yap
                            onPressed: (allSongs.isEmpty || isAllDownloaded) 
                                ? null 
                                : () => appState.downloadAllFromPlaylist(widget.playlistName, context),
                          ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 172, 25, 25), foregroundColor: Colors.white),
                      icon: const Icon(Icons.delete),
                      label: Text(appState.t('delete_playlist')),
                      onPressed: () {
                        appState.deletePlaylist(widget.playlistName);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: Colors.grey),
            Expanded(
              child: allSongs.isEmpty
                  ? Center(child: Text(appState.t('playlist_empty'), style: TextStyle(color: Colors.grey[600])))
                  : _isEditing
                      ? ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: EdgeInsets.only(top: 8, left: 8, right: 8, bottom: MediaQuery.of(context).padding.bottom + 80),
                          itemCount: allSongs.length,
                          onReorder: (oldIndex, newIndex) => appState.reorderPlaylist(widget.playlistName, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final song = allSongs[index];
                            return ReorderableDragStartListener(
                              index: index,
                              key: ValueKey("pl_${song['id']}"),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                      onPressed: () {
                                        appState.removeSongFromPlaylist(widget.playlistName, song['id']);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 40, height: 40, fit: BoxFit.cover)),
                                  ],
                                ),
                                title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(song['author'], maxLines: 1),
                                trailing: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.drag_handle, color: Colors.grey, size: 28)),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(top: 8, left: 8, right: 8, bottom: MediaQuery.of(context).padding.bottom + 80),
                          itemCount: allSongs.length,
                          itemBuilder: (context, index) {
                            final song = allSongs[index];
                            final isDownloaded = appState.downloadedSongs.any((s) => s['id'] == song['id']);
                            final isDownloading = appState.downloadingSongId == song['id'];
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                              title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(song['author'], maxLines: 1),
                              trailing: isDownloading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2))
                                  : isDownloaded 
                                    ? const Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 24) 
                                    : IconButton(
                                        icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey),
                                        onPressed: () => appState.downloadSpecificSong(song, context),
                                      ),
                              onTap: () => appState.playPlaylist(allSongs, context: context, startIndex: index, playlistName: widget.playlistName),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String formatDuration(Duration? duration) {
    if (duration == null) return "0:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final song = appState.currentSong;
    if (song == null) {
      return Scaffold(body: Center(child: Text(appState.t('no_song'))));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 32), onPressed: () => Navigator.pop(context)),
        title: Text(appState.t('now_playing'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(song['thumbnail'] ?? '', width: MediaQuery.of(context).size.width - 48, height: MediaQuery.of(context).size.width - 48, fit: BoxFit.cover)),
              const SizedBox(height: 32),
              Text(song['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(song['author'] ?? '', style: const TextStyle(fontSize: 18, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 32),
              StreamBuilder<Duration?>(
                stream: appState.player.durationStream,
                builder: (context, snapshot) {
                  final duration = snapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: appState.player.positionStream,
                    builder: (context, snapshot) {
                      var position = snapshot.data ?? Duration.zero;
                      if (position > duration) position = duration;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(trackHeight: 4.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0), activeTrackColor: const Color(0xFF1DB954), inactiveTrackColor: Colors.grey[800], thumbColor: Colors.white),
                            child: Slider(
                              min: 0.0,
                              max: duration.inMilliseconds.toDouble(),
                              value: position.inMilliseconds.toDouble(),
                              onChanged: (value) {
                                appState.seekAudio(Duration(milliseconds: value.toInt()));
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                Text(formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12))
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    iconSize: 28, 
                    icon: Icon(Icons.shuffle, color: appState.isShuffle ? const Color(0xFF1DB954) : Colors.grey), 
                    onPressed: () => appState.toggleShuffle()
                  ),
                  IconButton(iconSize: 48, icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: () => appState.playPrevious()),
                  IconButton(iconSize: 64, icon: Icon(appState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white), onPressed: () => appState.togglePlay()),
                  IconButton(iconSize: 48, icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: () => appState.playNext()),
                  IconButton(
                    iconSize: 28, 
                    icon: Icon(appState.isRepeat ? Icons.repeat_one : Icons.repeat, color: appState.isRepeat ? const Color(0xFF1DB954) : Colors.grey), 
                    onPressed: () => appState.toggleRepeat()
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.grey),
                  Expanded(
                    child: StreamBuilder<double>(
                      stream: appState.player.volumeStream,
                      builder: (context, snapshot) {
                        final volume = snapshot.data ?? 1.0;
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(trackHeight: 2.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0), activeTrackColor: Colors.white, inactiveTrackColor: Colors.grey[800], thumbColor: Colors.white),
                          child: Slider(
                            min: 0.0,
                            max: 1.0,
                            value: volume,
                            onChanged: (value) {
                              appState.setVolume(value);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}