# frozen_string_literal: true

module DiscourseVoiceMessages
  class VoiceMessage < ActiveRecord::Base
    self.table_name = "discourse_voice_messages_voice_messages"

    belongs_to :user

    has_one_attached :file

    validates :user_id, presence: true
    validates :chat_channel_id, presence: true

    # Finden von Nachrichten, die älter als X Tage sind
    def self.expired_messages
      return [] if SiteSetting.voice_messages_auto_delete_days <= 0

      where("created_at < ?", SiteSetting.voice_messages_auto_delete_days.days.ago)
    end

    # Löschen von abgelaufenen Nachrichten
    def self.cleanup_expired_messages
      return if SiteSetting.voice_messages_auto_delete_days <= 0

      expired = expired_messages

      if expired.any?
        # Zugehörige Chat-Nachrichten finden und löschen
        chat_message_ids = []
        expired.each do |voice_message|
          chat_messages = Chat::Message.where("metadata ->> 'voice_message_id' = ?", voice_message.id.to_s)
          chat_message_ids.concat(chat_messages.pluck(:id))
        end

        # Chat-Nachrichten löschen, wenn vorhanden
        Chat::Message.where(id: chat_message_ids).destroy_all if chat_message_ids.any?

        # Sprachnachrichten löschen
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
end