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
    dependencies: Deps,
    is_trusted_sender: Bool,
    is_admin: Bool,
    is_private_chat: Bool,
  )
}

pub type Resources {
  Resources(female_names: List(String), unicode_script_extensions: List(String))
}

pub type Deps {
  Deps(cas_check: fn(Int) -> Bool)
}

pub fn default(db: Subject(storage_message)) {
  BotSession(
    chat_settings: chat_settings.default(),
    user_chat: None,
    is_trusted_sender: False,
    is_admin: False,
    is_private_chat: False,
    db:,
    resources: Resources(female_names: [], unicode_script_extensions: []),
    dependencies: Deps(cas_check: fn(_) {
      panic as "ERR: cas_check was not injected! Some shit happened"
    }),
  )
}
