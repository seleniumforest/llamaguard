import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None}
import models/chat_settings.{type ChatSettings}
import models/error
import models/user_chat.{type UserChat}
import telega/storage.{type KeyValueStorage}
import telega/storage/ets

pub type BotSession(storage_message) {
  BotSession(
    //TODO move to telega's builder deps
    chat_settings: ChatSettings,
    user_chat: Option(UserChat),
    db: Subject(storage_message),
    resources: Resources,
    dependencies: Deps,
    is_trusted_sender: Bool,
    is_admin: Bool,
    is_private_chat: Bool,
    is_sender_newcomer: Bool,
    is_sender_non_member: fn() -> Bool,
    is_sender_a_chat: Bool,
    is_message_a_comment: Bool,
    real_sender: #(Int, Option(String)),
  )
}

pub type Resources {
  Resources(female_names: List(String), unicode_script_extensions: List(String))
}

pub type Deps {
  Deps(cas_check: fn(Int) -> Result(Int, error.BotError))
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
    real_sender: #(0, None),
    is_sender_newcomer: False,
    is_sender_non_member: fn() { False },
    is_sender_a_chat: False,
    is_message_a_comment: False,
  )
}
