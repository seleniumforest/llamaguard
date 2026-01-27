import gleam/erlang/process
import gleam/option
import models/chat_settings.{type ChatSettings}

pub type BotSession(storage_message) {
  BotSession(
    chat_settings: ChatSettings,
    db: process.Subject(storage_message),
    message_id: option.Option(Int),
    resources: Resources,
  )
}

pub type Resources {
  Resources(female_names: List(String))
}

pub fn default(db: process.Subject(storage_message)) {
  BotSession(
    chat_settings: chat_settings.default(),
    db:,
    message_id: option.None,
    resources: Resources(female_names: []),
  )
}
