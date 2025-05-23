# name: discourse-voice-messages
# about: Adds WhatsApp-like voice messaging to Discourse Chat
# version: 0.1
# authors: AI Assistant
# url: https://github.com/Goaloge/Discourse_voice_chat

register_asset "stylesheets/voice-messages.scss"

enabled_site_setting :voice_messages_enabled

PLUGIN_NAME ||= "discourse_voice_messages".freeze

after_initialize do
  # Sichere Tabellenerstellung ohne Migration
  unless ActiveRecord::Base.connection.table_exists?('discourse_voice_messages_voice_messages')
    ActiveRecord::Base.connection.create_table :discourse_voice_messages_voice_messages do |t|
      t.integer :user_id, null: false
      t.integer :chat_channel_id, null: false
      t.float :duration
      t.timestamps null: false
    end
    
    ActiveRecord::Base.connection.add_index :discourse_voice_messages_voice_messages, :user_id
    ActiveRecord::Base.connection.add_index :discourse_voice_messages_voice_messages, :chat_channel_id
  end

  # Rest des Plugin-Codes...
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
      channel_id = params[:chat_channel_id].to_i
      channel = Chat::Channel.find_by(id: channel_id)
      
      raise Discourse::InvalidAccess unless guardian.can_chat_in_channel?(channel)
      
      user_id = current_user.id
      
      voice_message = DiscourseVoiceMessages::VoiceMessage.create!(
        user_id: user_id,
        chat_channel_id: channel_id,
        duration: params[:duration].to_f
      )
      
      voice_message.file.attach(params[:file])
      
      chat_message = Chat::Message.create!(
        chat_channel: channel,
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
      
      if voice_message.nil?
        render json: { error: I18n.t("voice_messages.errors.not_found") }, status: 404
        return
      end
      
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
    
    def file_url
      return nil unless file.attached?
      Rails.application.routes.url_helpers.rails_blob_url(file, only_path: true)
    end
  end
  
  DiscourseVoiceMessages::Engine.routes.draw do
    post "/voice_messages" => "voice_messages#create"
    get "/voice_messages/:id" => "voice_messages#show"
  end
  
  Discourse::Application.routes.append do
    mount ::DiscourseVoiceMessages::Engine, at: "/voice-messages"
  end
  
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
