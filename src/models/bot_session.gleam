import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None}
import models/chat_settings.{type ChatSettings}
import models/user_chat.{type UserChat}

pub type BotSession(storage_message) {
  BotSession(
    chat_settings: ChatSettings,
    user_chat: Option(UserChat),
    db: Subject(storage_message),
    resources: Resources,
  )
}

pub type Resources {
  Resources(female_names: List(String), unicode_script_extensions: List(String))
}

pub fn default(db: Subject(storage_message)) {
  BotSession(
    chat_settings: chat_settings.default(),
    user_chat: None,
    db:,
    resources: Resources(female_names: [], unicode_script_extensions: []),
  )
}
