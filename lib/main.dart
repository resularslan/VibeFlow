import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart'; // YENİ EKLENDİ

void main() {
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
  // --- Arama Geçmişi Yönetimi ---
  final List<String> _searchHistory = [];
  List<String> get searchHistory => _searchHistory;

  void addToHistory(String query) {
    if (query.isNotEmpty && !_searchHistory.contains(query)) {
      _searchHistory.insert(0, query);
      notifyListeners();
    }
  }

  // --- Ses Oynatıcı (Audio Player) Yönetimi ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  
  bool get isPlaying => _isPlaying;

  MyAppState() {
    _initAudio();
  }

  Future<void> _initAudio() async {
    // Telifsiz, test amaçlı bir müzik URL'si kullanıyoruz
    const url = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
    try {
      await _audioPlayer.setUrl(url);
      
      // Şarkının çalıp çalmadığını (durumunu) dinliyoruz
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
    // appState üzerinden state verilerini dinliyoruz
    var appState = context.watch<MyAppState>();

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
              children: const [
                Text(
                  'Test Şarkısı (Online)',
                  style: TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  'Çevrimiçi',
                  style: TextStyle(
                    color: Colors.grey, 
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            // Şarkı çalıyorsa duraklatma (pause), çalmıyorsa oynatma (play) ikonu gösteriyoruz
            icon: Icon(
              appState.isPlaying ? Icons.pause : Icons.play_arrow, 
              color: Colors.white, 
              size: 32
            ),
            onPressed: () {
              // Butona basıldığında togglePlay metodunu tetikliyoruz
              appState.togglePlay();
            },
          ),
          const SizedBox(width: 8),
        ],
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

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

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
              "Search", 
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 16),
            SearchAnchor(
              builder: (BuildContext context, SearchController controller) {
                return SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: SearchBar(
                    hintText: "What do you want to listen to?",
                    hintStyle: WidgetStatePropertyAll<TextStyle>(
                      TextStyle(color: Colors.grey[400])
                    ),
                    backgroundColor: WidgetStatePropertyAll<Color>(
                      Colors.white.withOpacity(0.1)
                    ),
                    controller: controller,
                    padding: const WidgetStatePropertyAll<EdgeInsets>(
                      EdgeInsets.symmetric(horizontal: 16.0),
                    ),
                    onTap: () {
                      controller.openView();
                    },
                    onChanged: (value) {
                      controller.openView();
                    },
                    onSubmitted: (value) {
                      appState.addToHistory(value);
                      controller.closeView(value);
                    },
                    leading: const Icon(Icons.search, color: Colors.grey),
                  ),
                );
              },
              suggestionsBuilder: (BuildContext context, SearchController controller) {
                return appState.searchHistory.map((String item) {
                  return ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(item),
                    onTap: () {
                      controller.closeView(item);
                    },
                  );
                }).toList();
              },
            ),
            const SizedBox(height: 24),
            const Text(
              "Browse All", 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.primaries[index % Colors.primaries.length].withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Category ${index + 1}',
                      style: const TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white
                      ),
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
                "Your Library", 
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
            title: const Text('Add New Playlist'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              color: const Color(0xFF1DB954),
              child: const Icon(Icons.favorite, color: Colors.white),
            ),
            title: const Text('Liked Songs'),
            subtitle: const Text('Playlist • 120 songs'),
          ),
        ],
      ),
    );
  }
}