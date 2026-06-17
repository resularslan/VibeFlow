import 'dart:io';
import 'dart:convert';
import 'dart:async'; // Debounce için eklendi
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        title: 'My Music App',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1DB954),
            brightness: Brightness.dark,
            primary: const Color(0xFF1DB954),
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
  
  Map<dynamic, dynamic> _playlists = {};
  List<Map<dynamic, dynamic>> _downloadedSongs = [];
  List<Map<dynamic, dynamic>> _recentSongs = [];
  
  Map<dynamic, dynamic> get playlists => _playlists;
  List<Map<dynamic, dynamic>> get downloadedSongs => _downloadedSongs;
  List<Map<dynamic, dynamic>> get recentSongs => _recentSongs;

  // BULUT SUNUCUYU KURUNCA BURAYI DEĞİŞTİRECEĞİZ
  final String _backendUrl = "http://10.0.2.2:8000"; 

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
  bool _isPlaying = false;
  Map<dynamic, dynamic>? _currentSong; 

  bool get isPlaying => _isPlaying;
  Map<dynamic, dynamic>? get currentSong => _currentSong;

  MyAppState() {
    _initAudio();
    _loadData();
  }

  void _loadData() {
    final savedPlaylists = _libraryBox.get('custom_playlists', defaultValue: {});
    _playlists = Map<dynamic, dynamic>.from(savedPlaylists);

    final savedDownloads = _libraryBox.get('downloaded_songs', defaultValue: []);
    _downloadedSongs = List<Map<dynamic, dynamic>>.from(savedDownloads);

    final savedRecents = _libraryBox.get('recent_songs', defaultValue: []);
    _recentSongs = List<Map<dynamic, dynamic>>.from(savedRecents);
    
    notifyListeners();
  }

  void createPlaylist(String name) {
    if (name.isNotEmpty && !_playlists.containsKey(name)) {
      _playlists[name] = []; 
      _libraryBox.put('custom_playlists', _playlists);
      notifyListeners();
    }
  }

  // YENİ: İstenilen şarkıyı (sadece çalanı değil) listeye ekleyen esnek metod
  void addSongToPlaylist(String playlistName, Map<dynamic, dynamic> songToAdd) {
    if (_playlists.containsKey(playlistName)) {
      List songs = _playlists[playlistName];
      if (!songs.any((s) => s['id'] == songToAdd['id'])) {
        songs.add(songToAdd);
        _libraryBox.put('custom_playlists', _playlists);
        notifyListeners();
      }
    }
  }

  // YENİ: Çalma listesinden şarkı çıkarma
  void removeSongFromPlaylist(String playlistName, String songId) {
    if (_playlists.containsKey(playlistName)) {
      List songs = _playlists[playlistName];
      songs.removeWhere((s) => s['id'] == songId);
      _libraryBox.put('custom_playlists', _playlists);
      notifyListeners();
    }
  }

  // YENİ: Tıklanan şarkıyı geçmişin en üstüne ekler (Maksimum 10 şarkı tutar)
  void addToRecents(Map<dynamic, dynamic> song) {
    // Eğer şarkı zaten geçmişte varsa önce onu sil (tekrarlamayı önle ve en üste taşı)
    _recentSongs.removeWhere((s) => s['id'] == song['id']);
    
    _recentSongs.insert(0, song); // En başa ekle
    
    if (_recentSongs.length > 10) {
      _recentSongs.removeLast(); // 10'dan fazlaysa en eskisini sil
    }
    
    _libraryBox.put('recent_songs', _recentSongs);
    notifyListeners();
  }

  Future<void> performSearch(String query) async {
    if (query.isEmpty) return;

    _isSearching = true; 
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('$_backendUrl/search?query=${Uri.encodeComponent(query)}'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _searchResults = data['results']; 
        
      } else {
        _searchResults = [];
      }
    } catch (e) {
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
      notifyListeners();
    });
  }

  void seekAudio(Duration position) => _audioPlayer.seek(position);
  void setVolume(double volume) => _audioPlayer.setVolume(volume);

  Future<void> playOnlineSong(dynamic video) async {
    try {
      _currentSong = {
        'id': video['id'],
        'title': video['title'],
        'author': video['author'],
        'thumbnail': video['thumbnail'],
        'path': '', 
      };
      _isAudioLoading = true;
      notifyListeners();

      String streamUrl = "$_backendUrl/stream/${video['id']}";
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Akış hatası: $e");
    } finally {
      _isAudioLoading = false; 
      notifyListeners();
    }
  }

  Future<void> downloadCurrentSong() async {
    // Şarkı yoksa veya halihazırda herhangi bir indirme işlemi sürüyorsa durdur
    if (_currentSong == null || _downloadingSongId != null) return;

    // 1. KİLİT MEKANİZMASI: O anki şarkının verilerini anında fonksiyonun içine kopyalıyoruz.
    // Kullanıcı biz indirirken başka şarkıya geçse bile bu 'songToDownload' değişkeni asla değişmez!
    final songToDownload = Map<dynamic, dynamic>.from(_currentSong!);
    final targetId = songToDownload['id'];

    if (_downloadedSongs.any((s) => s['id'] == targetId)) return;

    // Durumu "Şu an bu ID iniyor" olarak güncelle
    _downloadingSongId = targetId;
    notifyListeners();

    File? file;
    IOSink? fileStream;

    try {
      String streamUrl = "$_backendUrl/stream/$targetId";
      var tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/$targetId.mp4';
      file = File(filePath);

      // 2. TIMEOUT (ZAMAN AŞIMI): Eğer sunucu 30 saniye içinde cevap vermezse işlemi iptal et ve sonsuz dönmeyi engelle
      final response = await http.Client().send(http.Request('GET', Uri.parse(streamUrl))).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200 || response.statusCode == 307) {
        fileStream = file.openWrite();
        await response.stream.pipe(fileStream);
        await fileStream.flush();
        await fileStream.close();

        // Kilitlediğimiz doğru veriyi kaydediyoruz
        songToDownload['path'] = filePath;
        
        _downloadedSongs.add(songToDownload);
        _libraryBox.put('downloaded_songs', _downloadedSongs);
      }
    } catch (e) {
      debugPrint("İndirme hatası veya zaman aşımı: $e");
      if (fileStream != null) await fileStream.close();
      if (file != null && await file.exists()) await file.delete();
    } finally {
      // Sadece inen şarkı buysa kilidi kaldır (başka bir işlem karışmasın diye)
      if (_downloadingSongId == targetId) {
        _downloadingSongId = null;
      }
      notifyListeners();
    }
  }

  Future<void> deleteDownloadedSong(String songId) async {
    final songIndex = _downloadedSongs.indexWhere((s) => s['id'] == songId);
    
    if (songIndex != -1) {
      final song = _downloadedSongs[songIndex];
      
      // 1. Fiziksel .mp4 dosyasını cihazdan sil
      try {
        final file = File(song['path']);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint("Dosya silinirken hata: $e");
      }

      // 2. Şarkıyı listeden ve veritabanından çıkar
      _downloadedSongs.removeAt(songIndex);
      _libraryBox.put('downloaded_songs', _downloadedSongs);
      notifyListeners();
    }
  }

  Future<void> playOfflineSong(Map<dynamic, dynamic> song) async {
    try {
      _currentSong = song;
      _isAudioLoading = true;
      notifyListeners();

      File file = File(song['path']);
      if (await file.exists()) {
        await _audioPlayer.setAudioSource(AudioSource.file(song['path']));
        _audioPlayer.play();
      } else {
        throw Exception("Dosya bulunamadı.");
      }
    } catch (e) {
      debugPrint("Çevrimdışı çalma hatası: $e");
    } finally {
      _isAudioLoading = false;
      notifyListeners();
    }
  }

  void togglePlay() {
    if (_isPlaying) _audioPlayer.pause();
    else _audioPlayer.play();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// YENİ: Ortak Çalma Listesi Seçim Menüsü
void showPlaylistSelectionSheet(BuildContext context, MyAppState appState, Map<dynamic, dynamic> songToSave) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    builder: (context) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Çalma Listesine Ekle", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (appState.playlists.isEmpty)
            const Padding(padding: EdgeInsets.all(16.0), child: Text("Önce Kütüphane'den bir liste oluşturun.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center))
          else
            ...appState.playlists.keys.map((playlistName) => ListTile(
              leading: const Icon(Icons.queue_music, color: Colors.white),
              title: Text(playlistName, style: const TextStyle(color: Colors.white)),
              onTap: () {
                appState.addSongToPlaylist(playlistName, songToSave);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$playlistName' listesine eklendi!", style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1DB954)));
              },
            )).toList(),
        ],
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
    Widget page;
    switch (selectedIndex) {
      case 0: page = const HomePage(); break;
      case 1: page = const SearchPage(); break;
      case 2: page = const LibraryPage(); break;
      default: throw UnimplementedError('Hatalı sayfa');
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: page),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) { setState(() { selectedIndex = index; }); },
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFF1DB954).withOpacity(0.3),
        selectedIndex: selectedIndex,
        destinations: const <Widget>[
          NavigationDestination(selectedIcon: Icon(Icons.home, color: Colors.white), icon: Icon(Icons.home_outlined, color: Colors.grey), label: 'Home'),
          NavigationDestination(selectedIcon: Icon(Icons.search, color: Colors.white), icon: Icon(Icons.search_outlined, color: Colors.grey), label: 'Search'),
          NavigationDestination(selectedIcon: Icon(Icons.library_music, color: Colors.white), icon: Icon(Icons.library_music_outlined, color: Colors.grey), label: 'Library')
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
    final hasSong = appState.currentSong != null;
    final isDownloaded = hasSong && appState.downloadedSongs.any((s) => s['id'] == appState.currentSong!['id']);

    return Container(
      height: 64,
      decoration: const BoxDecoration(color: Color(0xFF181818), border: Border(bottom: BorderSide(color: Colors.black, width: 1))),
      child: Row(
        children: [
          Container(
            width: 64, height: 64, color: Colors.grey[850],
            child: hasSong
                ? Image.network(appState.currentSong!['thumbnail'], fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.white, size: 32))
                : const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () { if (hasSong) Navigator.push(context, MaterialPageRoute(builder: (context) => const PlayerScreen())); },
              onLongPress: () { if (hasSong) showPlaylistSelectionSheet(context, appState, appState.currentSong!); },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hasSong ? appState.currentSong!['title'] : 'Henüz Şarkı Seçilmedi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    appState.isAudioLoading ? 'Bağlanıyor...' : (isDownloaded ? 'Cihazda Kayıtlı' : 'Çevrimiçi Akış'),
                    style: const TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          if (appState.downloadingSongId == appState.currentSong!['id'])
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2))
            )
          else if (hasSong && !isDownloaded && !appState.isAudioLoading)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey, size: 28),
              onPressed: () { appState.downloadCurrentSong(); }
            )
          else if (isDownloaded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 28)
            ),
          IconButton(icon: Icon(appState.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32), onPressed: (hasSong && !appState.isAudioLoading) ? () => appState.togglePlay() : null),
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
            const Text("Arama", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: SearchBar(
                controller: _searchController,
                hintText: "Ne dinlemek istiyorsun?",
                hintStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(color: Colors.grey[400]!)),
                backgroundColor: WidgetStatePropertyAll<Color>(Colors.white.withOpacity(0.1)),
                padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.symmetric(horizontal: 16.0)),
                leading: const Icon(Icons.search, color: Colors.grey),
                trailing: _searchController.text.isNotEmpty
                    ? [IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { 
                        _searchController.clear(); appState.clearSearchResults(); setState(() {}); 
                      })] : null,
                // YENİ: Yazarken bekleme (Debounce) ile canlı arama
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 500), () {
                    if (value.isNotEmpty) appState.performSearch(value);
                    else appState.clearSearchResults();
                  });
                  setState(() {}); 
                },
              ),
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: _searchController.text.isEmpty
                  // 1. DURUM: ARAMA ÇUBUĞU BOŞSA SON TIKLANAN ŞARKILARI GÖSTER
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (appState.recentSongs.isNotEmpty) ...[
                          const Text("Son Çalınanlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: appState.recentSongs.length,
                              itemBuilder: (context, index) {
                                final video = appState.recentSongs[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(video['thumbnail'], width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: 64, height: 48, color: Colors.grey[800], child: const Icon(Icons.music_note))),
                                  ),
                                  title: Text(video['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(video['author'], maxLines: 1),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
                                        onPressed: () => showPlaylistSelectionSheet(context, appState, video),
                                      ),
                                      const Icon(Icons.play_arrow, color: Colors.grey),
                                    ],
                                  ),
                                  onTap: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    appState.addToRecents(video); // Tıklanınca geçmişte en üste taşı
                                    appState.playOnlineSong(video); 
                                  },
                                );
                              },
                            ),
                          ),
                        ] else
                          Center(child: Text("Aramak istediğiniz şarkıyı yazın.", style: TextStyle(color: Colors.grey[500], fontSize: 16))),
                      ],
                    )
                  // 2. DURUM: ARAMA ÇUBUĞU DOLUYSA SONUÇLARI GÖSTER
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
                              'path': '',
                            };

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(video['thumbnail'], width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: 64, height: 48, color: Colors.grey[800], child: const Icon(Icons.music_note))),
                              ),
                              title: Text(video['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(video['author'], maxLines: 1),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
                                    onPressed: () => showPlaylistSelectionSheet(context, appState, mapVideo),
                                  ),
                                  const Icon(Icons.play_arrow, color: Colors.grey),
                                ],
                              ),
                              onTap: () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                appState.addToRecents(mapVideo); // YENİ: Şarkıya tıklandığında onu geçmişe kaydet
                                appState.playOnlineSong(video); 
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

// YENİ: Dinamik Ana Sayfa
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
            const Text('Hoş Geldin', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            if (appState.playlists.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: const [
                    Icon(Icons.queue_music, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text("Henüz buralar çok sessiz.", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text("Kütüphaneden ilk çalma listeni oluşturarak başlayabilirsin.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                  ],
                ),
              )
            else ...[
              const Text("Senin Listelerin", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        children: [
                          Container(width: 56, color: Colors.grey[800], child: const Icon(Icons.music_note)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(playlistName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
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

class DownloadedSongsPage extends StatelessWidget {
  const DownloadedSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return Scaffold(
      appBar: AppBar(title: const Text("İndirilen Şarkılar"), backgroundColor: Colors.black),
      body: appState.downloadedSongs.isEmpty
          ? Center(child: Text("Henüz indirilen şarkı yok.", style: TextStyle(color: Colors.grey[600])))
          : ListView.builder(
              padding: const EdgeInsets.all(16), itemCount: appState.downloadedSongs.length,
              itemBuilder: (context, index) {
                final song = appState.downloadedSongs[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                  leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                  title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song['author'], maxLines: 1),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      appState.deleteDownloadedSong(song['id']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${song['title']} cihazdan silindi."),
                          backgroundColor: Colors.redAccent,
                          duration: const Duration(seconds: 2),
                        )
                      );
                    },
                  ),
                  onTap: () { appState.playOfflineSong(song); },
                );
              },
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
          Row(children: const [CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)), SizedBox(width: 16), Text("Kütüphanen", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: Container(width: 50, height: 50, color: Colors.grey[800], child: const Icon(Icons.add)),
            title: const Text('Yeni Çalma Listesi Oluştur'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  final TextEditingController controller = TextEditingController();
                  return AlertDialog(
                    backgroundColor: Colors.grey[900], title: const Text('Yeni Çalma Listesi', style: TextStyle(color: Colors.white)),
                    content: TextField(controller: controller, style: const TextStyle(color: Colors.white), autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
                      TextButton(onPressed: () { appState.createPlaylist(controller.text); Navigator.pop(context); }, child: const Text('Oluştur', style: TextStyle(color: Color(0xFF1DB954)))),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: Container(width: 50, height: 50, color: const Color(0xFF1DB954), child: const Icon(Icons.download_done, color: Colors.white)),
            title: const Text('İndirilen Şarkılar'), subtitle: Text('${appState.downloadedSongs.length} şarkı • Çevrimdışı hazır'), trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadedSongsPage())); },
          ),
          const SizedBox(height: 16), const Divider(color: Colors.black), const SizedBox(height: 16),
          ...appState.playlists.entries.map((entry) => ListTile(
            contentPadding: EdgeInsets.zero, leading: Container(width: 50, height: 50, color: Colors.grey[850], child: const Icon(Icons.queue_music, color: Colors.white)),
            title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${entry.value.length} Şarkı'), trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailsPage(playlistName: entry.key))); },
          )).toList(),
        ],
      ),
    );
  }
}

class PlaylistDetailsPage extends StatelessWidget {
  final String playlistName;
  const PlaylistDetailsPage({super.key, required this.playlistName});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    List songs = appState.playlists[playlistName] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(playlistName), backgroundColor: Colors.black),
      body: songs.isEmpty
          ? Center(child: Text("Bu liste henüz boş.", style: TextStyle(color: Colors.grey[600])))
          : ListView.builder(
              padding: const EdgeInsets.all(16), itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                  leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                  title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song['author'], maxLines: 1),
                  // YENİ: Listeden çıkarma butonu
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                    onPressed: () { appState.removeSongFromPlaylist(playlistName, song['id']); },
                  ),
                  onTap: () {
                    final isDownloaded = appState.downloadedSongs.any((s) => s['id'] == song['id']);
                    if (isDownloaded) appState.playOfflineSong(song);
                    else appState.playOnlineSong(song);
                  },
                );
              },
            ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String formatDuration(Duration? duration) {
    if (duration == null) return "0:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final song = appState.currentSong;

    if (song == null) return const Scaffold(body: Center(child: Text("Şarkı Yok")));

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 32), onPressed: () => Navigator.pop(context)), title: const Text("Şimdi Çalıyor", style: TextStyle(fontSize: 14, color: Colors.grey)), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(song['thumbnail'], width: MediaQuery.of(context).size.width - 48, height: MediaQuery.of(context).size.width - 48, fit: BoxFit.cover)),
            const SizedBox(height: 32),
            Text(song['title'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(song['author'], style: const TextStyle(fontSize: 18, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          data: SliderTheme.of(context).copyWith(trackHeight: 4.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0), overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0), activeTrackColor: const Color(0xFF1DB954), inactiveTrackColor: Colors.grey[800], thumbColor: Colors.white),
                          child: Slider(min: 0.0, max: duration.inMilliseconds.toDouble(), value: position.inMilliseconds.toDouble(), onChanged: (value) { appState.seekAudio(Duration(milliseconds: value.toInt())); }),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12))])),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(iconSize: 64, icon: Icon(appState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white), onPressed: () => appState.togglePlay())]),
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
                        child: Slider(min: 0.0, max: 1.0, value: volume, onChanged: (value) { appState.setVolume(value); }),
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
    );
  }
}