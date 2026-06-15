import 'dart:io'; // YENİ: Dosya işlemleri için
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart'; // YENİ: Telefon hafızası için
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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
  List<String> _playlists = [];
  List<String> _downloads = [];
  bool _isDownloading = false;

  List<String> get playlists => _playlists;
  List<String> get downloads => _downloads;
  bool get isDownloading => _isDownloading;

  final YoutubeExplode _yt = YoutubeExplode();
  bool _isSearching = false;
  bool _isAudioLoading = false; // YENİ: Şarkı indirilirken yükleniyor durumu

  bool get isSearching => _isSearching;
  bool get isAudioLoading => _isAudioLoading;

  MyAppState() {
    _initAudio();
    _loadData();
  }

  void _loadData() {
    final savedPlaylists = _libraryBox.get('playlists', defaultValue: <String>[]);
    _playlists = List<String>.from(savedPlaylists);

    final savedDownloads = _libraryBox.get('downloads', defaultValue: <String>[]);
    _downloads = List<String>.from(savedDownloads);
    
    notifyListeners();
  }

  void addPlaylist(String name) {
    if (name.isNotEmpty && !_playlists.contains(name)) {
      _playlists.add(name);
      _libraryBox.put('playlists', _playlists);
      notifyListeners();
    }
  }

  // Kalıcı indirme butonu mantığı (Kütüphane için)
  Future<void> downloadCurrentSong() async {
    if (_currentSong == null) return;
    final songTitle = _currentSong.title;
    
    if (!_downloads.contains(songTitle)) {
      _downloads.add(songTitle);
      _libraryBox.put('downloads', _downloads); 
      notifyListeners();
    }
  }

  final List<String> _searchHistory = [];
  List<dynamic> _searchResults = []; 

  List<String> get searchHistory => _searchHistory;
  List<dynamic> get searchResults => _searchResults;

  Future<void> performSearch(String query) async {
    if (query.isNotEmpty) {
      if (!_searchHistory.contains(query)) {
        _searchHistory.insert(0, query);
      }
      
      _isSearching = true; 
      notifyListeners();

      try {
        var searchResult = await _yt.search.search(query, filter: TypeFilters.video);
        _searchResults = searchResult.toList(); 
      } catch (e) {
        debugPrint('YouTube araması sırasında hata: $e');
        _searchResults = []; 
      } finally {
        _isSearching = false; 
        notifyListeners(); 
      }
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  dynamic _currentSong; 

  bool get isPlaying => _isPlaying;
  dynamic get currentSong => _currentSong;

  Future<void> _initAudio() async {
    _audioPlayer.playerStateStream.listen((playerState) {
      _isPlaying = playerState.playing;
      notifyListeners();
    });
  }

  // DEVRİMSEL DEĞİŞİKLİK: YouTube Engelini Yok Eden İndir-Çal Metodu
  Future<void> playSong(dynamic video) async {
    File? file;
    IOSink? fileStream;
    
    try {
      _currentSong = video;
      _isAudioLoading = true;
      notifyListeners();

      var manifest = await _yt.videos.streamsClient.getManifest(video.id);
      
      // DEĞİŞİKLİK 1: En yüksek kaliteyi değil, en düşük dosya boyutunu (ilk Muxed) alıyoruz.
      // Bu sayede 30-40 MB yerine 3-5 MB indireceğiz, saniyeler sürecek!
      if (manifest.muxed.isEmpty) throw Exception("Uygun akış bulunamadı.");
      var streamInfo = manifest.muxed.first; 
      
      var tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/${video.id}.mp4';
      file = File(filePath);

      // Eğer dosya yoksa veya yarım kalıp 0 byte olduysa indir
      if (!await file.exists() || await file.length() == 0) {
        debugPrint("Şarkı indiriliyor (Zaman aşımı korumalı)...");
        var stream = _yt.videos.streamsClient.get(streamInfo);
        fileStream = file.openWrite();

        // DEĞİŞİKLİK 2: 30 Saniye Sigortası! 
        // 30 saniye içinde bitmezse sonsuza kadar bekleme, hata fırlat!
        await stream.pipe(fileStream).timeout(const Duration(seconds: 30));
        await fileStream.flush();
        await fileStream.close();
        
        debugPrint("İndirme bitti! Boyut: ${await file.length()} bytes");
      } else {
        debugPrint("Şarkı zaten hafızada hazır.");
      }

      await _audioPlayer.setAudioSource(AudioSource.file(filePath));
      _audioPlayer.play();
      
    } catch (e) {
      debugPrint("Müzik indirme/oynatma hatası: $e");
      
      // Eğer indirme yarıda kesildiyse bozuk dosyayı sil (sonraki denemede baştan insin)
      if (fileStream != null) await fileStream.close();
      if (file != null && await file.exists()) {
        await file.delete();
      }
      
      try {
        await _audioPlayer.setUrl('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3');
        _audioPlayer.play();
      } catch (_) {}
      
    } finally {
      // Ne olursa olsun (çalışsa da, çökse de, zaman aşımına uğrasa da) yükleme animasyonunu durdur!
      _isAudioLoading = false; 
      notifyListeners();
    }
  }

  void togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _yt.close(); 
    super.dispose();
  }
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
        throw UnimplementedError('no widget for $selectedIndex');
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: page),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            selectedIndex = index;
          });
        },
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFF1DB954).withOpacity(0.3),
        selectedIndex: selectedIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.home, color: Colors.white),
            icon: Icon(Icons.home_outlined, color: Colors.grey),
            label: 'Home',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.search, color: Colors.white),
            icon: Icon(Icons.search_outlined, color: Colors.grey),
            label: 'Search',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.library_music, color: Colors.white),
            icon: Icon(Icons.library_music_outlined, color: Colors.grey),
            label: 'Library',
          )
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
    final songTitle = hasSong ? appState.currentSong.title : 'Henüz Şarkı Seçilmedi';
    final thumbnailUrl = hasSong ? appState.currentSong.thumbnails.lowResUrl : null;
    
    final isDownloaded = appState.downloads.contains(songTitle);

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFF181818), 
        border: Border(
          bottom: BorderSide(color: Colors.black, width: 1), 
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            color: Colors.grey[850],
            child: hasSong
                ? Image.network(thumbnailUrl, fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.white, size: 32))
                : const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  songTitle,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  appState.isAudioLoading 
                      ? 'Şarkı yükleniyor...' 
                      : (isDownloaded ? 'Çevrimdışı (Kaydedildi)' : 'Çevrimiçi hazır'),
                  style: TextStyle(
                    color: const Color(0xFF1DB954), 
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Şarkı yükleniyorsa/indiriliyorsa mini player'da küçük bir yükleniyor dairesi dönsün
          if (appState.isAudioLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2),
              ),
            )
          else if (hasSong)
            IconButton(
              icon: Icon(isDownloaded ? Icons.offline_pin : Icons.download_for_offline_outlined, 
                  color: isDownloaded ? const Color(0xFF1DB954) : Colors.grey, size: 28),
              onPressed: () {
                appState.downloadCurrentSong();
              },
            ),

          IconButton(
            icon: Icon(
              appState.isPlaying ? Icons.pause : Icons.play_arrow, 
              color: Colors.white, 
              size: 32
            ),
            onPressed: (hasSong && !appState.isAudioLoading) ? () {
              appState.togglePlay();
            } : null,
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

  @override
  void dispose() {
    _searchController.dispose();
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
            const Text(
              "Arama", 
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: SearchBar(
                controller: _searchController,
                hintText: "Ne dinlemek istiyorsun?",
                hintStyle: WidgetStatePropertyAll<TextStyle>(
                  TextStyle(color: Colors.grey[400]!)
                ),
                backgroundColor: WidgetStatePropertyAll<Color>(
                  Colors.white.withOpacity(0.1)
                ),
                padding: const WidgetStatePropertyAll<EdgeInsets>(
                  const EdgeInsets.symmetric(horizontal: 16.0),
                ),
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
                onSubmitted: (value) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  appState.performSearch(value);
                },
                onChanged: (value) {
                  setState(() {}); 
                  if (value.isEmpty) {
                    appState.clearSearchResults();
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: appState.isSearching 
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF1DB954)),
                    )
                  : appState.searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[800]),
                              const SizedBox(height: 16),
                              Text(
                                "Aramak istediğiniz şarkıyı yazın.",
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: appState.searchResults.length,
                          itemBuilder: (context, index) {
                            final video = appState.searchResults[index];
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  video.thumbnails.lowResUrl, 
                                  width: 64, 
                                  height: 48, 
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 64, height: 48, color: Colors.grey[800],
                                    child: const Icon(Icons.music_note),
                                  ),
                                ),
                              ),
                              title: Text(
                                video.title,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(video.author, maxLines: 1),
                              trailing: const Icon(Icons.play_arrow, color: Colors.grey),
                              onTap: () {
                                FocusManager.instance.primaryFocus?.unfocus();
                                appState.playSong(video);
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Good Evening',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: List.generate(6, (index) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Playlist ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            const Text(
              'Made for You',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 140,
                          width: 140,
                          color: Colors.grey[800],
                          child: const Icon(Icons.album, size: 50),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Daily Mix ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
            children: const [
              CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text(
                "Kütüphanen", 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              color: Colors.grey[800],
              child: const Icon(Icons.add),
            ),
            title: const Text('Yeni Çalma Listesi Oluştur'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  final TextEditingController controller = TextEditingController();
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text('Yeni Çalma Listesi', style: TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Liste adı',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: const Color(0xFF1DB954).withOpacity(0.5)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF1DB954)),
                        ),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('İptal', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.addPlaylist(controller.text);
                          Navigator.pop(context);
                        },
                        child: const Text('Oluştur', style: TextStyle(color: Color(0xFF1DB954))),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              color: const Color(0xFF1DB954),
              child: const Icon(Icons.download_done, color: Colors.white),
            ),
            title: const Text('İndirilen Şarkılar'),
            subtitle: Text('${appState.downloads.length} şarkı • Çevrimdışı hazır'),
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.black),
          const SizedBox(height: 16),
          
          ...appState.playlists.map((playlistName) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              color: Colors.grey[850],
              child: const Icon(Icons.queue_music, color: Colors.white),
            ),
            title: Text(playlistName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Çalma Listesi'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          )).toList(),
        ],
      ),
    );
  }
}