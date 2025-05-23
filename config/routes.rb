# frozen_string_literal: true

DiscourseVoiceMessages::Engine.routes.draw do
  post "/voice_messages" => "voice_messages#create"
  get "/voice_messages/:id" => "voice_messages#show"
end