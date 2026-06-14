import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'; // YouTube motoru

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
  
  bool get isSearching => _isSearching;

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

  Future<void> downloadCurrentSong() async {
    const currentSongName = 'Test Şarkısı (SoundHelix)';
    
    if (!_downloads.contains(currentSongName)) {
      _isDownloading = true;
      notifyListeners();

      await Future.delayed(const Duration(seconds: 2));

      _downloads.add(currentSongName);
      _libraryBox.put('downloads', _downloads); 
      
      _isDownloading = false;
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
  
  bool get isPlaying => _isPlaying;

  Future<void> _initAudio() async {
    const url = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
    try {
      await _audioPlayer.setUrl(url);
      _audioPlayer.playerStateStream.listen((playerState) {
        final isPlaying = playerState.playing;
        final processingState = playerState.processingState;
        
        if (processingState == ProcessingState.completed) {
          _isPlaying = false;
          notifyListeners();
        } else {
          _isPlaying = isPlaying;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("Ses yüklenirken hata oluştu: $e");
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
    final isDownloaded = appState.downloads.contains('Test Şarkısı (SoundHelix)');

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
            child: const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Test Şarkısı (SoundHelix)',
                  style: TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isDownloaded ? 'Çevrimdışı (İndirildi)' : 'Çevrimiçi',
                  style: TextStyle(
                    color: isDownloaded ? const Color(0xFF1DB954) : Colors.grey, 
                    fontSize: 12,
                    fontWeight: isDownloaded ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          
          if (appState.isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Color(0xFF1DB954), strokeWidth: 2),
              ),
            )
          else if (isDownloaded)
            const IconButton(
              icon: Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 28),
              onPressed: null, 
            )
          else
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined, color: Colors.grey, size: 28),
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
            onPressed: () {
              appState.togglePlay();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// GÜNCELLENEN KISIM: Arama Sayfası (Gerçek Veriler)
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
                  // Arama butonuna basıldığında klavyeyi kapat ve aramayı başlat
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
            
            // Sonuçları Gösteren Alan
            Expanded(
              child: appState.isSearching 
                  // 1. Durum: Arama yapılıyorsa yükleniyor animasyonu göster
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF1DB954)),
                    )
                  // 2. Durum: Sonuç boşsa varsayılan metni göster
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
                      // 3. Durum: YouTube'dan veri geldiyse listele
                      : ListView.builder(
                          itemCount: appState.searchResults.length,
                          itemBuilder: (context, index) {
                            final video = appState.searchResults[index];
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                              // YENİ: YouTube kapak fotoğrafı
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
                              // YENİ: YouTube Video Başlığı
                              title: Text(
                                video.title,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // YENİ: Kanal Adı
                              subtitle: Text(video.author, maxLines: 1),
                              trailing: const Icon(Icons.play_arrow, color: Colors.grey),
                              onTap: () {
                                // Tıklanma olayı Görev 8'de buraya eklenecek!
                                debugPrint("Seçilen şarkı ID'si: ${video.id}");
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