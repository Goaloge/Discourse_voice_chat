# name: discourse-voice-messages
# about: Adds WhatsApp-like voice messaging to Discourse Chat
# version: 0.1
# authors: AI Assistant
# url: https://github.com/discourse/discourse-voice-messages

register_asset "stylesheets/voice-messages.scss"

enabled_site_setting :voice_messages_enabled

PLUGIN_NAME ||= "discourse_voice_messages".freeze

after_initialize do
  # Täglichen Aufräum-Job für alte Sprachnachrichten einrichten
  if defined?(Jobs) && SiteSetting.voice_messages_enabled
    module ::Jobs
      class CleanupExpiredVoiceMessages < ::Jobs::Scheduled
        every 1.day

        def execute(args)
          return unless SiteSetting.voice_messages_enabled
          return if SiteSetting.voice_messages_auto_delete_days <= 0

          ::DiscourseVoiceMessages::VoiceMessage.cleanup_expired_messages
        end
      end
    end
  end
  module ::DiscourseVoiceMessages
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseVoiceMessages
    end
  end

  require_dependency "application_controller"

  class DiscourseVoiceMessages::VoiceMessagesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in

    def create
      params.require(:file)
      user_id = current_user.id

      # Store the uploaded voice message
      voice_message = DiscourseVoiceMessages::VoiceMessage.create!(
        user_id: user_id,
        chat_channel_id: params[:chat_channel_id],
        file: params[:file]
      )

      # Create a chat message with the voice message
      chat_message = Chat::Message.create!(
        chat_channel_id: params[:chat_channel_id],
        user_id: user_id,
        message: "",
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
      voice_message = DiscourseVoiceMessages::VoiceMessage.find_by(id: params[:id])

      if voice_message.nil? || !guardian.can_see_chat_channel?(voice_message.chat_channel_id)
        render json: { error: I18n.t("voice_messages.errors.not_found") }, status: 404
        return
      end

      render json: {
        id: voice_message.id,
        url: voice_message.file_url,
        duration: voice_message.duration,
        user_id: voice_message.user_id,
        created_at: voice_message.created_at
      }
    end
  end

  class DiscourseVoiceMessages::VoiceMessage < ActiveRecord::Base
    belongs_to :user

    has_one_attached :file

    validates :user_id, presence: true
    validates :chat_channel_id, presence: true

    def file_url
      Rails.application.routes.url_helpers.rails_blob_url(file, only_path: true)
    end
  end

  # Add table for voice messages
  on_activate do
    ActiveRecord::Schema.define(migration_version) do
      create_table :discourse_voice_messages_voice_messages do |t|
        t.integer :user_id, null: false
        t.integer :chat_channel_id, null: false
        t.float :duration
        t.timestamps null: false
      end

      add_index :discourse_voice_messages_voice_messages, :user_id
      add_index :discourse_voice_messages_voice_messages, :chat_channel_id
    end
  end

  # Register the routes
  DiscourseVoiceMessages::Engine.routes.draw do
    post "/voice_messages" => "voice_messages#create"
    get "/voice_messages/:id" => "voice_messages#show"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseVoiceMessages::Engine, at: "/voice-messages"
  end

  # Register message decorator to display voice messages
  on_mount do
    MessageBus.subscribe("/chat/#{SiteSetting.chat_channel_id}") do |message|
      if message.data["voice_message_id"]
        voice_message = DiscourseVoiceMessages::VoiceMessage.find_by(id: message.data["voice_message_id"])
        if voice_message
          message.data["voice_message"] = {
            id: voice_message.id,
            url: voice_message.file_url,
            duration: voice_message.duration
          }
        end
      end
    end
  end

  # Add to serializer
  add_to_serializer(:chat_message, :voice_message) do
    if object.metadata && object.metadata["voice_message_id"]
      voice_message = DiscourseVoiceMessages::VoiceMessage.find_by(id: object.metadata["voice_message_id"])
      {
        id: voice_message.id,
        url: voice_message.file_url,
        duration: voice_message.duration
      } if voice_message
    end
  end

  add_to_serializer(:chat_message, :include_voice_message?) do
    object.metadata && object.metadata["voice_message_id"]
  end
end