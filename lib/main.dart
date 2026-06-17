import 'dart:io';
import 'dart:convert';
import 'dart:async';
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

  // --- AKILLI OYNATMA KUYRUĞU VE TRUE SHUFFLE MOTORU ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  AudioPlayer get player => _audioPlayer;

  List<Map<dynamic, dynamic>> _queue = [];
  int _queueIndex = 0;
  bool _isPlaying = false;
  bool _isShuffle = false;
  Map<dynamic, dynamic>? _currentSong;

  List<int> _shuffledIndices = [];
  int _shuffledPointer = 0;

  bool get isPlaying => _isPlaying;
  bool get isShuffle => _isShuffle;
  Map<dynamic, dynamic>? get currentSong => _currentSong;

  MyAppState() {
    _initAudio();
    _loadData();
  }

  void _loadData() {
    _playlists = Map<dynamic, dynamic>.from(_libraryBox.get('custom_playlists', defaultValue: {}));
    _downloadedSongs = List<Map<dynamic, dynamic>>.from(_libraryBox.get('downloaded_songs', defaultValue: []));
    _recentSongs = List<Map<dynamic, dynamic>>.from(_libraryBox.get('recent_songs', defaultValue: []));
    notifyListeners();
  }

  // --- ÇALMA LİSTESİ DÜZENLEME ---
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

  void reorderPlaylist(String playlistName, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = _playlists[playlistName].removeAt(oldIndex);
    _playlists[playlistName].insert(newIndex, item);
    _libraryBox.put('custom_playlists', _playlists);
    notifyListeners();
  }

  void reorderDownloadedSongs(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = _downloadedSongs.removeAt(oldIndex);
    _downloadedSongs.insert(newIndex, item);
    _libraryBox.put('downloaded_songs', _downloadedSongs);
    notifyListeners();
  }

  // --- SON ÇALINANLAR KONTROLÜ ---
  void addToRecents(Map<dynamic, dynamic> song) {
    _recentSongs.removeWhere((s) => s['id'] == song['id']);
    _recentSongs.insert(0, song);
    if (_recentSongs.length > 10) {
      _recentSongs.removeLast();
    }
    _libraryBox.put('recent_songs', _recentSongs);
    notifyListeners();
  }

  void removeFromRecents(String songId) {
    _recentSongs.removeWhere((s) => s['id'] == songId);
    _libraryBox.put('recent_songs', _recentSongs);
    notifyListeners();
  }

  // --- ARAMA ---
  Future<void> performSearch(String query) async {
    if (query.isEmpty) {
      return;
    }
    _isSearching = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse('$_backendUrl/search?query=${Uri.encodeComponent(query)}'));
      if (response.statusCode == 200) {
        _searchResults = json.decode(response.body)['results'];
      } else {
        _searchResults = [];
      }
    } catch (_) {
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

  // --- BAĞLAM VE HAVUZLU SEÇİM MOTORU ---
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
      int currentInQueue = _queue.indexWhere((s) => s['id'] == _currentSong?['id']);
      if (currentInQueue != -1) {
        _shuffledIndices.remove(currentInQueue);
        _shuffledIndices.insert(0, currentInQueue);
      }
      _shuffledPointer = 0;
    }
    notifyListeners();
  }

  void playSingleSong(dynamic video, {BuildContext? context}) {
    final mapVideo = {
      'id': video['id'],
      'title': video['title'],
      'author': video['author'],
      'thumbnail': video['thumbnail'],
      'path': video['path'] ?? ''
    };
    _queue = [mapVideo];
    _queueIndex = 0;
    _playCurrentQueueItem(context: context);
  }

  void playPlaylist(List songs, int startIndex, {BuildContext? context}) {
    if (songs.isEmpty) {
      return;
    }
    _queue = List<Map<dynamic, dynamic>>.from(songs);

    if (_isShuffle) {
      _shuffledIndices = List.generate(_queue.length, (i) => i)..shuffle();
      _shuffledPointer = _shuffledIndices.indexOf(startIndex);
      if (_shuffledPointer == -1) {
        _shuffledPointer = 0;
      }
      _queueIndex = _shuffledIndices[_shuffledPointer];
    } else {
      _queueIndex = startIndex;
    }
    _playCurrentQueueItem(context: context);
  }

  void playNext({BuildContext? context}) {
    if (_queue.isEmpty) {
      return;
    }

    if (_isShuffle) {
      _shuffledPointer++;
      if (_shuffledPointer >= _shuffledIndices.length) {
        _shuffledIndices.shuffle();
        _shuffledPointer = 0;
      }
      _queueIndex = _shuffledIndices[_shuffledPointer];
    } else {
      _queueIndex++;
      if (_queueIndex >= _queue.length) {
        _queueIndex = 0;
        _audioPlayer.stop();
        _isPlaying = false;
        notifyListeners();
        return;
      }
    }
    _playCurrentQueueItem(context: context);
  }

  void playPrevious({BuildContext? context}) {
    if (_queue.isEmpty) {
      return;
    }
    if (_isShuffle) {
      _shuffledPointer--;
      if (_shuffledPointer < 0) {
        _shuffledPointer = _shuffledIndices.length - 1;
      }
      _queueIndex = _shuffledIndices[_shuffledPointer];
    } else {
      _queueIndex--;
      if (_queueIndex < 0) {
        _queueIndex = 0;
      }
    }
    _playCurrentQueueItem(context: context);
  }

  Future<void> _playCurrentQueueItem({BuildContext? context}) async {
    if (_queue.isEmpty || _queueIndex >= _queue.length) {
      return;
    }

    var song = _queue[_queueIndex];
    _currentSong = song;
    _isAudioLoading = true;
    notifyListeners();

    var dlMatch = _downloadedSongs.firstWhere((s) => s['id'] == song['id'], orElse: () => {});

    try {
      if (dlMatch.isNotEmpty) {
        File file = File(dlMatch['path']);
        if (await file.exists()) {
          await _audioPlayer.setAudioSource(AudioSource.file(dlMatch['path']));
          _audioPlayer.play();
        } else {
          throw Exception("Dosya bozuk.");
        }
      } else {
        String streamUrl = "$_backendUrl/stream/${song['id']}";
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
        _audioPlayer.play();
      }
    } catch (_) {
      final localContext = context;
      if (localContext != null && localContext.mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(
            content: Text("${song['title']} atlandı (İnternet veya dosya hatası)"),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      playNext(context: context);
      return;
    } finally {
      // YAZIM HATASI BURADAYDI! (final yerine finally olması gerekiyor)
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

  // --- İNDİRME ---
  Future<void> downloadSpecificSong(Map<dynamic, dynamic> songToDownload, BuildContext context) async {
    final targetId = songToDownload['id'];
    if (_downloadedSongs.any((s) => s['id'] == targetId) || _downloadingSongId != null) {
      return;
    }

    _downloadingSongId = targetId;
    notifyListeners();

    File? file;
    IOSink? fileStream;
    try {
      String streamUrl = "$_backendUrl/stream/$targetId";
      var tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/$targetId.mp4';
      file = File(filePath);

      final response = await http.Client().send(http.Request('GET', Uri.parse(streamUrl))).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 307) {
        fileStream = file.openWrite();
        await response.stream.pipe(fileStream);
        await fileStream.flush();
        await fileStream.close();

        final savedSong = Map<dynamic, dynamic>.from(songToDownload);
        savedSong['path'] = filePath;
        _downloadedSongs.add(savedSong);
        _libraryBox.put('downloaded_songs', _downloadedSongs);
        
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Şarkı başarıyla indirildi!"), backgroundColor: Color(0xFF1DB954)),
        );
      }
    } catch (_) {
      if (fileStream != null) {
        await fileStream.close();
      }
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } finally {
      if (_downloadingSongId == targetId) {
        _downloadingSongId = null;
      }
      notifyListeners();
    }
  }

  Future<void> deleteDownloadedSong(String songId) async {
    final songIndex = _downloadedSongs.indexWhere((s) => s['id'] == songId);
    if (songIndex != -1) {
      try {
        final file = File(_downloadedSongs[songIndex]['path']);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _downloadedSongs.removeAt(songIndex);
      _libraryBox.put('downloaded_songs', _downloadedSongs);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// Alt Menü
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
            ...appState.playlists.keys.map((playlistName) {
              return ListTile(
                leading: const Icon(Icons.queue_music, color: Colors.white),
                title: Text(playlistName, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  appState.addSongToPlaylist(playlistName, songToSave);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$playlistName' listesine eklendi!"), backgroundColor: const Color(0xFF1DB954)));
                },
              );
            }),
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
    final song = appState.currentSong;
    final hasSong = song != null;
    final isDownloaded = hasSong && appState.downloadedSongs.any((s) => s['id'] == song['id']);

    return Container(
      height: 64,
      decoration: const BoxDecoration(color: Color(0xFF181818), border: Border(bottom: BorderSide(color: Colors.black, width: 1))),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            color: Colors.grey[850],
            child: hasSong
                ? Image.network(song['thumbnail'] ?? '', fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.music_note, color: Colors.white, size: 32))
                : const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (hasSong) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const PlayerScreen()));
                }
              },
              onLongPress: () {
                if (hasSong) {
                  showPlaylistSelectionSheet(context, appState, song);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hasSong ? song['title'] : 'Henüz Şarkı Seçilmedi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(appState.isAudioLoading ? 'Bağlanıyor...' : (isDownloaded ? 'Cihazda Kayıtlı' : (hasSong ? 'Çevrimiçi Akış' : '')), style: const TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
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
              width: double.infinity,
              height: 50,
              child: SearchBar(
                controller: _searchController,
                hintText: "Ne dinlemek istiyorsun?",
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
                          const Text("Son Çalınanlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                          Center(child: Text("Aramak istediğiniz şarkıyı yazın.", style: TextStyle(color: Colors.grey[500], fontSize: 16))),
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
            const Text('Hoş Geldin', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (appState.playlists.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: const [
                    Icon(Icons.queue_music, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text("Henüz buralar çok sessiz.", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text("Kütüphaneden ilk çalma listeni oluşturarak başlayabilirsin.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center)
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
        title: const Text("İndirilen Şarkılar"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: Icon(_isEditing ? Icons.check : Icons.edit, color: const Color(0xFF1DB954)), onPressed: () => setState(() => _isEditing = !_isEditing))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Oynat"),
                  onPressed: allSongs.isEmpty ? null : () => appState.playPlaylist(allSongs, 0, context: context),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: appState.isShuffle ? const Color(0xFF1DB954) : Colors.grey[800], foregroundColor: Colors.white),
                  icon: const Icon(Icons.shuffle),
                  label: Text(appState.isShuffle ? "Karışık (Açık)" : "Karışık (Kapalı)"),
                  onPressed: allSongs.isEmpty ? null : () => appState.toggleShuffle(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.grey),
          Expanded(
            child: allSongs.isEmpty
                ? Center(child: Text("Henüz indirilen şarkı yok.", style: TextStyle(color: Colors.grey[600])))
                : _isEditing
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.all(8),
                        itemCount: allSongs.length,
                        onReorder: (oldIndex, newIndex) => appState.reorderDownloadedSongs(oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final song = allSongs[index];
                          return ReorderableDragStartListener(
                            index: index,
                            key: ValueKey("dl_${song['id']}_$index"),
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
                        padding: const EdgeInsets.all(8),
                        itemCount: allSongs.length,
                        itemBuilder: (context, index) {
                          final song = allSongs[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                            leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                            title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song['author'], maxLines: 1),
                            trailing: const Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 20),
                            onTap: () => appState.playPlaylist(allSongs, index, context: context),
                          );
                        },
                      ),
          ),
        ],
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
              CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)),
              SizedBox(width: 16),
              Text("Kütüphanen", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(width: 50, height: 50, color: Colors.grey[800], child: const Icon(Icons.add)),
            title: const Text('Yeni Çalma Listesi Oluştur'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  final TextEditingController controller = TextEditingController();
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text('Yeni Çalma Listesi', style: TextStyle(color: Colors.white)),
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
            title: const Text('İndirilen Şarkılar'),
            subtitle: Text('${appState.downloadedSongs.length} şarkı • Çevrimdışı hazır'),
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
              subtitle: Text('${entry.value.length} Şarkı'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: Icon(_isEditing ? Icons.check : Icons.edit, color: const Color(0xFF1DB954)), onPressed: () => setState(() => _isEditing = !_isEditing))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.white),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Oynat"),
                  onPressed: allSongs.isEmpty ? null : () => appState.playPlaylist(allSongs, 0, context: context),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: appState.isShuffle ? const Color(0xFF1DB954) : Colors.grey[800], foregroundColor: Colors.white),
                  icon: const Icon(Icons.shuffle),
                  label: Text(appState.isShuffle ? "Karışık (Açık)" : "Karışık (Kapalı)"),
                  onPressed: allSongs.isEmpty ? null : () => appState.toggleShuffle(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.grey),
          Expanded(
            child: allSongs.isEmpty
                ? Center(child: Text("Bu liste boş.", style: TextStyle(color: Colors.grey[600])))
                : _isEditing
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.all(8),
                        itemCount: allSongs.length,
                        onReorder: (oldIndex, newIndex) => appState.reorderPlaylist(widget.playlistName, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final song = allSongs[index];
                          return ReorderableDragStartListener(
                            index: index,
                            key: ValueKey("pl_${song['id']}_$index"),
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
                        padding: const EdgeInsets.all(8),
                        itemCount: allSongs.length,
                        itemBuilder: (context, index) {
                          final song = allSongs[index];
                          final isDownloaded = appState.downloadedSongs.any((s) => s['id'] == song['id']);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                            leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song['thumbnail'], width: 50, height: 50, fit: BoxFit.cover)),
                            title: Text(song['title'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song['author'], maxLines: 1),
                            trailing: isDownloaded ? const Icon(Icons.offline_pin, color: Color(0xFF1DB954), size: 20) : null,
                            onTap: () => appState.playPlaylist(allSongs, index, context: context),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String formatDuration(Duration? duration) {
    if (duration == null) {
      return "0:00";
    }
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${duration.inHours > 0 ? '${duration.inHours}:' : ''}${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    final song = appState.currentSong;
    if (song == null) {
      return const Scaffold(body: Center(child: Text("Şarkı Yok")));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 32), onPressed: () => Navigator.pop(context)),
        title: const Text("Şimdi Çalıyor", style: TextStyle(fontSize: 14, color: Colors.grey)),
        centerTitle: true,
      ),
      body: Padding(
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
                    if (position > duration) {
                      position = duration;
                    }
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(iconSize: 48, icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: () => appState.playPrevious()),
                IconButton(iconSize: 64, icon: Icon(appState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white), onPressed: () => appState.togglePlay()),
                IconButton(iconSize: 48, icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: () => appState.playNext()),
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
    );
  }
}