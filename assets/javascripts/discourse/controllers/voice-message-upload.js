import Controller from "@ember/controller";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default Controller.extend({
  isUploading: false,

  actions: {
    uploadVoiceMessage(audioBlob, channelId, duration) {
      this.set('isUploading', true);

      const formData = new FormData();
      formData.append('file', audioBlob, 'voice-message.mp3');
      formData.append('chat_channel_id', channelId);
      formData.append('duration', duration);

      return ajax("/voice-messages/voice_messages", {
        type: "POST",
        processData: false,
        contentType: false,
        data: formData
      })
        .then(response => {
          return response;
        })
        .catch(error => {
          popupAjaxError(error);
          throw error;
        })
        .finally(() => {
          this.set('isUploading', false);
        });
    }
  }
});