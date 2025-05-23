# frozen_string_literal: true

class CreateVoiceMessages < ActiveRecord::Migration[7.0]
  def up
    create_table :discourse_voice_messages_voice_messages do |t|
      t.integer :user_id, null: false
      t.integer :chat_channel_id, null: false
      t.float :duration
      t.timestamps null: false
    end

    add_index :discourse_voice_messages_voice_messages, :user_id
    add_index :discourse_voice_messages_voice_messages, :chat_channel_id
  end

  def down
    drop_table :discourse_voice_messages_voice_messages
  end
end