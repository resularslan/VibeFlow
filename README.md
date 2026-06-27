# VibeFlow 🎵 (Flutter Music Architecture Experiment)

This is an open-source educational project developed to explore advanced application architecture, state management, and project lifecycle through **"vibe coding"** (AI-assisted development). Even this text is generated with AI.

### 🧠 The "Vibe Coding" Journey
I started this project with zero prior knowledge of Flutter or Dart. The entire development process is driven by AI assistance. My primary goal isn't just to write code, but to learn:
* How complex software projects are structured and managed.
* How to communicate effectively with AI to build a full, production-ready application.
* The overall lifecycle of client-side mobile application development.

### Video Demo: https://github.com/user-attachments/assets/a7fe14e3-3dfd-4596-8ee5-b191c2f24517

### 🔥 Key Engineering Highlights
While this is a learning experiment, it implements several advanced architectural concepts:
* **Zero-Latency Audio Prefetching:** A custom background algorithm that prepares the next track's data stream while the current song is playing, eliminating gap times.
* **Dynamic Live Queue:** An advanced, industry-standard queue algorithm that dynamically updates and syncs with playlist modifications in real-time, handling complex shuffle and repeat states seamlessly.
* **Background Audio Services:** Deep integration with Android/iOS native media notification controls for persistent background playback.
* **Ultra-Fast Local Storage:** Implementation of a NoSQL database for encrypted, offline-first library and history management.
* **Instant Localization:** Seamless, state-driven UI translations (English/Turkish) without requiring app reboots.

### 🛠 Tech Stack
* **Framework:** Flutter (Dart)
* **Audio Engine:** `just_audio` & `just_audio_background`
* **API Wrappers:** * `ytmusicapi_dart` (InnerTube search & metadata integration)
  * `youtube_explode_dart` (Direct audio stream extraction)
* **State Management:** Provider (Centralized app state & event system)
* **Local Storage:** Hive (NoSQL local caching) & `path_provider` (Native file system access for offline downloads)
* **Development Approach:** AI-Assisted "Vibe Coding"

### 🚧 Purpose & Legal Disclaimer
* **Use at your own risk:** This project is provided for **educational and research purposes only.** The author assumes no responsibility or liability for any misuse of this software, violation of third-party Terms of Service, or any other damages arising from its use.
* **No Commercial Intent:** It is NOT intended for commercial use or distribution. 
* **No Hosted Content:** VibeFlow acts strictly as a client-side interface demonstration and does not host, store, or distribute any copyrighted media content. All data is served directly from public APIs.
* **No Binaries:** This application is a Proof of Concept (PoC). No compiled APK binaries are distributed within this repository.
