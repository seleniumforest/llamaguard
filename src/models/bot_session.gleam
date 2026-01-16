import gleam/erlang/process
import gleam/option
import models/chat_settings.{type ChatSettings}
import storage

pub type BotSession {
  BotSession(
    chat_settings: ChatSettings,
    db: process.Subject(storage.StorageMessage),
    message_id: option.Option(Int),
    resources: Resources,
  )
}

pub type Resources {
  Resources(female_names: List(String))
}

pub fn default(db: process.Subject(storage.StorageMessage)) {
  BotSession(
    chat_settings: chat_settings.default(),
    db:,
    message_id: option.None,
    resources: Resources(female_names: []),
  )
}
