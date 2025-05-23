# frozen_string_literal: true

module DiscourseVoiceMessages
  class VoiceMessagesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in

    def create
      params.require(:file)

      # Ensure the user has permission to post in this channel
      channel_id = params[:chat_channel_id].to_i
      channel = Chat::Channel.find_by(id: channel_id)

      raise Discourse::InvalidAccess unless guardian.can_chat_in_channel?(channel)

      user_id = current_user.id

      # Store the voice message with ActiveStorage
      voice_message = VoiceMessage.create!(
        user_id: user_id,
        chat_channel_id: channel_id,
        duration: params[:duration].to_f
      )

      # Attach the uploaded file
      voice_message.file.attach(params[:file])

      # Create a chat message with a reference to the voice message
      chat_message = Chat::Message.create!(
        chat_channel: channel,
        user_id: user_id,
        message: "", # Empty text message
        metadata: { voice_message_id: voice_message.id }
      )

      render json: {
        success: true,
        voice_message_id: voice_message.id,
        chat_message_id: chat_message.id,
        url: voice_message.file_url
      }
    end

    def show
      voice_message = VoiceMessage.find_by(id: params[:id])

      if voice_message.nil?
        render json: { error: I18n.t("voice_messages.errors.not_found") }, status: 404
        return
      end

      # Check if the user can see the channel where this voice message was posted
      channel = Chat::Channel.find_by(id: voice_message.chat_channel_id)

      raise Discourse::InvalidAccess unless guardian.can_chat_in_channel?(channel)

      render json: {
        id: voice_message.id,
        url: voice_message.file_url,
        duration: voice_message.duration,
        user_id: voice_message.user_id,
        created_at: voice_message.created_at
      }
    end
  end
end