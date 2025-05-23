import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "voice-message-button",

  initialize() {
    withPluginApi("0.8.7", (api) => {
      api.addChatComposerButton({
        id: "voice-message",
        icon: "microphone",
        label: "Sprachnachricht",
        title: "Sprachnachricht aufnehmen oder hochladen",
        action: () => handleVoiceRecording(api),
      });
    });

    let mediaRecorder;
    let audioChunks = [];
    let recording = false;

    function isMediaRecorderSupported() {
      return !!(navigator.mediaDevices && window.MediaRecorder);
    }

    async function handleVoiceRecording(api) {
      if (recording) {
        mediaRecorder.stop();
        recording = false;
        return;
      }

      if (isMediaRecorderSupported()) {
        return startMediaRecorder(api);
      } else {
        return fallbackFileUpload();
      }
    }

    async function startMediaRecorder(api) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

        mediaRecorder = new MediaRecorder(stream, {
          mimeType: MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/ogg"
        });

        audioChunks = [];
        recording = true;
        alert("🎙️ Aufnahme gestartet. Klicke erneut, um sie zu beenden.");

        mediaRecorder.ondataavailable = (e) => audioChunks.push(e.data);

        mediaRecorder.onstop = async () => {
          const audioBlob = new Blob(audioChunks, { type: mediaRecorder.mimeType });
          const file = new File([audioBlob], "sprachnachricht.webm");

          await uploadAudio(file);
        };

        mediaRecorder.start();
      } catch (err) {
        alert("🎤 Zugriff auf Mikrofon verweigert oder nicht verfügbar.");
        console.error(err);
      }
    }

    function fallbackFileUpload() {
      const fileInput = document.createElement("input");
      fileInput.type = "file";
      fileInput.accept = "audio/*";

      fileInput.addEventListener("change", async (e) => {
        const file = e.target.files[0];
        if (file) {
          await uploadAudio(file);
        }
      });

      fileInput.click();
    }

    async function uploadAudio(file) {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("type", "composer");

      try {
        const response = await fetch("/uploads.json", {
          method: "POST",
          body: formData,
          headers: {
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
          },
        });

        const data = await response.json();
        if (data && data.url) {
          const composerModel = require("discourse/models/composer").default;
          composerModel.appendText(`<audio controls src="${data.url}"></audio>`);
        } else {
          alert("❌ Fehler beim Upload.");
        }
      } catch (err) {
        alert("❌ Upload fehlgeschlagen.");
        console.error(err);
      }
    }
  },
};
