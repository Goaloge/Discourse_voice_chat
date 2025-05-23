import Component from "@ember/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";

export default Component.extend({
  classNames: ["voice-recorder-component"],
  isRecording: false,
  recordingTime: 0,
  mediaRecorder: null,
  audioChunks: null,
  timer: null,
  maxDuration: 300, // Maximum recording duration in seconds (5 minutes)
  isMobileDevice: false,

  didInsertElement() {
    this._super(...arguments);

    // Erkennen, ob es sich um ein mobiles Gerät handelt
    this.set('isMobileDevice', this.detectMobileDevice());

    // Auf mobilen Geräten warten wir mit dem Mikrofon-Zugriff bis der Nutzer auf Record klickt
    if (!this.isMobileDevice) {
      this.requestMicrophoneAccess();
    }
  },

  willDestroyElement() {
    this._super(...arguments);
    this.stopRecording();
    this.stopTimer();

    if (this.audioStream) {
      this.audioStream.getTracks().forEach(track => track.stop());
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

  @action
  async requestMicrophoneAccess() {
    try {
      // Optimierte Audio-Einstellungen für mobile Geräte
      const audioConstraints = {
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        }
      };

      const stream = await navigator.mediaDevices.getUserMedia(audioConstraints);
      this.set('audioStream', stream);
      this.set('microphoneAccessGranted', true);

      // Wenn der Nutzer auf "Aufnehmen" geklickt hat, starten wir direkt die Aufnahme
      if (this.waitingToRecord) {
        this.set('waitingToRecord', false);
        this.startRecording();
      }
    } catch (error) {
      console.error("Error accessing microphone:", error);
      this.set('microphoneAccessError', true);
    }
  },

  @action
  startRecording() {
    if (!this.audioStream) {
      // Auf mobilen Geräten wird der Mikrofon-Zugriff erst jetzt angefordert
      this.set('waitingToRecord', true);
      this.requestMicrophoneAccess();
      return;
    }

    this.set('audioChunks', []);

    // Optimierte Einstellungen für bessere Kompatibilität
    let options = {};

    // Verschiedene Formate testen für beste Browser-Kompatibilität
    if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
      options = {
        mimeType: 'audio/webm;codecs=opus',
        audioBitsPerSecond: this.isMobileDevice ? 24000 : 32000 // Niedrigere Bitrate für mobile Geräte
      };
    } else if (MediaRecorder.isTypeSupported('audio/mp4')) {
      options = {
        mimeType: 'audio/mp4',
        audioBitsPerSecond: this.isMobileDevice ? 24000 : 32000
      };
    }

    try {
      const mediaRecorder = new MediaRecorder(this.audioStream, options);
      this.set('mediaRecorder', mediaRecorder);

      mediaRecorder.addEventListener('dataavailable', (event) => {
        if (event.data.size > 0) {
          this.audioChunks.push(event.data);
        }
      });

      mediaRecorder.addEventListener('stop', () => {
        this.processRecording();
      });

      // Häufigere Chunks für mobile Geräte (bessere Benutzerfreundlichkeit bei Verbindungsabbrüchen)
      const chunkInterval = this.isMobileDevice ? 250 : 100;
      mediaRecorder.start(chunkInterval);

      this.set('isRecording', true);
      this.set('recordingTime', 0);
      this.startTimer();
    } catch (error) {
      console.error("Error starting recording:", error);
      this.set('recordingError', true);
    }
  },

  @action
  stopRecording() {
    if (this.mediaRecorder && this.isRecording) {
      this.mediaRecorder.stop();
      this.set('isRecording', false);
      this.stopTimer();
    }
  },

  @action
  cancelRecording() {
    this.stopRecording();
    this.set('audioChunks', []);
    this.sendAction('onCancel');
  },

  startTimer() {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.incrementProperty('recordingTime');

      // Stop recording if max duration is reached
      if (this.recordingTime >= this.maxDuration) {
        this.stopRecording();
      }
    }, 1000);
  },

  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  },

  processRecording() {
    if (this.audioChunks && this.audioChunks.length > 0) {
      let audioType = 'audio/mp3';

      // Auf verschiedenen Browsern verschiedene Formate verwenden
      if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
        audioType = 'audio/webm';
      } else if (MediaRecorder.isTypeSupported('audio/mp4')) {
        audioType = 'audio/mp4';
      }

      // Convert audio chunks to blob
      const audioBlob = new Blob(this.audioChunks, { type: audioType });

      // Zu kurze Aufnahmen nicht senden (unter 1 Sekunde)
      if (this.recordingTime < 1) {
        this.cancelRecording();
        return;
      }

      // Send the recorded audio up to the parent component
      this.sendAction('onRecorded', audioBlob, this.recordingTime);
    }
  },

  formattedTime: function() {
    const minutes = Math.floor(this.recordingTime / 60);
    const seconds = this.recordingTime % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }.property('recordingTime')
});