package com.example.my_music_app

import io.flutter.embedding.android.FlutterActivity
import com.ryanheise.audioservice.AudioServiceActivity // YENİ EKLENDİ

// YENİ: Normal FlutterActivity yerine AudioServiceActivity kullanıyoruz
class MainActivity: AudioServiceActivity() {
}