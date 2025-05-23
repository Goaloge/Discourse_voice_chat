import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Component from "@ember/component";

export default {
  name: "discourse-voice-messages",

  initialize(container) {
    withPluginApi("0.8.31", api => {
      // Register components
      api.container.lookup('chat-composer:main').reopen({
        actions: {
          // Add voice message button to chat composer
          toggleVoiceRecorder() {
            if (this.showVoiceRecorder) {
              this.set('showVoiceRecorder', false);
            } else {
              this.set('showVoiceRecorder', true);
            }
          },

          // Handle successful voice message recording
          voiceMessageRecorded(audioBlob, duration) {
            this.set('showVoiceRecorder', false);
            this.sendVoiceMessage(audioBlob, duration);
          }
        },

        // Send the voice message to the server
        sendVoiceMessage(audioBlob, duration) {
          const formData = new FormData();
          formData.append('file', audioBlob, 'voice-message.mp3');
          formData.append('chat_channel_id', this.channel.id);
          formData.append('duration', duration);

          this.set('isSubmitting', true);

          ajax("/voice-messages/voice_messages", {
            type: "POST",
            processData: false,
            contentType: false,
            data: formData
          })
            .then(response => {
              if (response.success) {
                // Voice message was sent and chat message created
                this.appEvents.trigger("chat:refresh-channel", this.channel);
              }
            })
            .catch(popupAjaxError)
            .finally(() => {
              this.set('isSubmitting', false);
            });
        }
      });

      // Add button to chat composer toolbar
      api.decorateChatComposerButtons((buttons, chatComposer) => {
        buttons.push({
          id: "voice-message",
          action: "toggleVoiceRecorder",
          icon: "microphone",
          title: "voice_messages.record",
          classNames: ["voice-message-button"]
        });

        return buttons;
      });

      // Register custom message renderer for voice messages
      api.decorateChatMessage((message, chatMessage, chatChannel) => {
        if (chatMessage.voice_message) {
          message.querySelectorAll('.chat-message-text').forEach(e => {
            // Create voice player component
            const voicePlayer = document.createElement('div');
            voicePlayer.classList.add('voice-message-player');

            const audio = document.createElement('audio');
            audio.src = chatMessage.voice_message.url;
            audio.controls = true;

            const duration = document.createElement('span');
            duration.classList.add('voice-message-duration');
            duration.textContent = formatDuration(chatMessage.voice_message.duration || 0);

            voicePlayer.appendChild(audio);
            voicePlayer.appendChild(duration);

            e.appendChild(voicePlayer);
          });
        }

        return message;
      });

      // Helper to format duration in mm:ss
      function formatDuration(seconds) {
        const minutes = Math.floor(seconds / 60);
        const remainingSeconds = Math.floor(seconds % 60);
        return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
      }
    });
  }
};