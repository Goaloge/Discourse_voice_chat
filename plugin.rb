# name: discourse_voice_chat
# about: Ermöglicht Sprachnachrichten im Discourse-Chat mit Safari-Fallback
# version: 0.2
# authors: Dein Name
# url: https://github.com/deinname/discourse_voice_chat

enabled_site_setting :voice_messages_enabled

register_asset "javascripts/discourse/chat/voice-message-button.js", :client_side
