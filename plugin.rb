# name: discourse-voice-messages
# about: Adds WhatsApp-like voice messaging to Discourse Chat
# version: 0.1
# authors: AI Assistant
# url: https://github.com/Goaloge/Discourse_voice_chat

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
      
      # Ensure the user has permission to post in this channel
      channel_id = params[:chat_channel_id].to_i
      channel = Chat::Channel.find_by(id: channel_id)
      
      raise Discourse::InvalidAccess unless guardian.can_chat_in_channel?(channel)
      
      user_id = current_user.id
      
      # Store the voice message with ActiveStorage
      voice_message = DiscourseVoiceMessages::VoiceMessage.create!(
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
      voice_message = DiscourseVoiceMessages::VoiceMessage.find_by(id: params[:id])
      
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
  
  class DiscourseVoiceMessages::VoiceMessage < ActiveRecord::Base
    self.table_name = "discourse_voice_messages_voice_messages"
    
    belongs_to :user
    
    has_one_attached :file
    
    validates :user_id, presence: true
    validates :chat_channel_id, presence: true
    
    def self.expired_messages
      return [] if SiteSetting.voice_messages_auto_delete_days <= 0
      
      where("created_at < ?", SiteSetting.voice_messages_auto_delete_days.days.ago)
    end
    
    def self.cleanup_expired_messages
      return if SiteSetting.voice_messages_auto_delete_days <= 0
      
      expired = expired_messages
      
      if expired.any?
        chat_message_ids = []
        expired.each do |voice_message|
          chat_messages = Chat::Message.where("metadata ->> 'voice_message_id' = ?", voice_message.id.to_s)
          chat_message_ids.concat(chat_messages.pluck(:id))
        end
        
        Chat::Message.where(id: chat_message_ids).destroy_all if chat_message_ids.any?
        expired.destroy_all
      end
    end
    
    def file_url
      return nil unless file.attached?
      
      Rails.application.routes.url_helpers.rails_blob_url(
        file,
        only_path: true
      )
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
  
  # Add to serializer
  add_to_serializer(:chat_message, :voice_message) do
    if object.metadata && object.metadata["voice_message_id"]
      voice_message = DiscourseVoiceMessages::VoiceMessage.find_by(id: object.metadata["voice_message_id"])
      if voice_message
        {
          id: voice_message.id,
          url: voice_message.file_url,
          duration: voice_message.duration
        }
      end
    end
  end
  
  add_to_serializer(:chat_message, :include_voice_message?) do
    object.metadata && object.metadata["voice_message_id"]
  end
end
