import gleam/erlang/process
import models/chat_settings.{type ChatSettings}

pub type BotSession(storage_message) {
  BotSession(
    chat_settings: ChatSettings,
    db: process.Subject(storage_message),
    resources: Resources,
  )
}

pub type Resources {
  Resources(female_names: List(String), unicode_script_extensions: List(String))
}

pub fn default(db: process.Subject(storage_message)) {
  BotSession(
    chat_settings: chat_settings.default(),
    db:,
    resources: Resources(female_names: [], unicode_script_extensions: []),
  )
}
