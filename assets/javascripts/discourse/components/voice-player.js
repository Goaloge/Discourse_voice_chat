import Component from "@ember/component";
import { action } from "@ember/object";

export default Component.extend({
  classNames: ["voice-player-component"],
  isPlaying: false,
  progress: 0,
  audio: null,
  duration: 0,
  currentTime: 0,
  isMobileDevice: false,

  didInsertElement() {
    this._super(...arguments);

    // Erkennen ob es ein mobiles Gerät ist
    this.set('isMobileDevice', this.detectMobileDevice());

    this.setupAudio();

    // Touch-Events für mobile Geräte hinzufügen
    if (this.isMobileDevice) {
      const progressBar = this.element.querySelector('.progress-bar');
      if (progressBar) {
        progressBar.addEventListener('touchstart', this.handleTouchSeek.bind(this));
        progressBar.addEventListener('touchmove', this.handleTouchSeek.bind(this));
      }
    }
  },

  willDestroyElement() {
    this._super(...arguments);

    // Touch-Event-Listener entfernen
    if (this.isMobileDevice) {
      const progressBar = this.element.querySelector('.progress-bar');
      if (progressBar) {
        progressBar.removeEventListener('touchstart', this.handleTouchSeek.bind(this));
        progressBar.removeEventListener('touchmove', this.handleTouchSeek.bind(this));
      }
    }

    if (this.audio) {
      this.audio.pause();
      this.audio.src = "";
      this.audio.remove();
    }
  },

  // Erkennung von mobilen Geräten
  detectMobileDevice() {
    const userAgent = navigator.userAgent || navigator.vendor || window.opera;

    // Prüfen auf iOS oder Android
    if (/android|iPad|iPhone|iPod/.test(userAgent) && !window.MSStream) {
      return true;
    }

    // Weitere Erkennung über Bildschirmbreite
    return window.innerWidth <= 768;
  },

  setupAudio() {
    const audio = new Audio(this.url);
    this.set('audio', audio);

    // Audio-Vorladung für schnellere Wiedergabe
    audio.preload = "auto";

    audio.addEventListener('loadedmetadata', () => {
      this.set('duration', audio.duration);
    });

    audio.addEventListener('timeupdate', () => {
      this.set('currentTime', audio.currentTime);
      this.set('progress', (audio.currentTime / audio.duration) * 100);
    });

    audio.addEventListener('ended', () => {
      this.set('isPlaying', false);
      this.set('progress', 0);
      this.set('currentTime', 0);
      audio.currentTime = 0;
    });

    audio.addEventListener('pause', () => {
      this.set('isPlaying', false);
    });

    audio.addEventListener('play', () => {
      this.set('isPlaying', true);
    });

    // Fehlerbehandlung hinzufügen
    audio.addEventListener('error', (e) => {
      console.error("Error loading audio:", e);
      this.set('audioError', true);
    });

    // Set initial duration if available from the message metadata
    if (this.messageDuration) {
      this.set('duration', this.messageDuration);
    }
  },

  @action
  togglePlay() {
    if (this.isPlaying) {
      this.audio.pause();
    } else {
      // Pause any other playing audio elements
      document.querySelectorAll('audio').forEach(audio => audio.pause());

      // Wiedergabeversuch mit Fehlerbehandlung
      const playPromise = this.audio.play();

      if (playPromise !== undefined) {
        playPromise.catch(error => {
          console.error("Playback failed:", error);
          // Möglicherweise Autoplay-Einschränkungen
          this.set('playbackError', true);
        });
      }
    }
  },

  @action
  seek(event) {
    // Verhindern von Bubbling
    event.stopPropagation();

    const progressBar = event.currentTarget;
    const clickPosition = (event.clientX - progressBar.getBoundingClientRect().left) / progressBar.offsetWidth;
    const seekTime = this.duration * clickPosition;

    if (this.audio && !isNaN(seekTime) && isFinite(seekTime)) {
      this.audio.currentTime = seekTime;
    }
  },

  // Spezieller Handler für Touch-Events auf mobilen Geräten
  handleTouchSeek(event) {
    // Verhindern von Scroll-Events während der Benutzung des Sliders
    event.preventDefault();

    const touch = event.touches[0];
    const progressBar = event.currentTarget;
    const touchPosition = (touch.clientX - progressBar.getBoundingClientRect().left) / progressBar.offsetWidth;
    const seekTime = this.duration * touchPosition;

    if (this.audio && !isNaN(seekTime) && isFinite(seekTime) && touchPosition >= 0 && touchPosition <= 1) {
      this.audio.currentTime = seekTime;
    }
  },

  formattedCurrentTime: function() {
    return this.formatTime(this.currentTime);
  }.property('currentTime'),

  formattedDuration: function() {
    return this.formatTime(this.duration);
  }.property('duration'),

  formatTime(seconds) {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }
});