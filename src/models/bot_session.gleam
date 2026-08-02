import gleam/json
import gleam/option.{type Option, None}
import gleam/string
import models/chat_settings.{type ChatSettings}
import models/user_chat.{type UserChat}

pub type BotSession {
  BotSession(
    //TODO move to telega's builder deps
    chat_settings: ChatSettings,
    user_chat: Option(UserChat),
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

pub fn session_encoder(session: BotSession) {
  json.object([
    #("is_trusted_sender", json.bool(session.is_trusted_sender)),
    #("is_admin", json.bool(session.is_admin)),
    #("is_private_chat", json.bool(session.is_private_chat)),
    #("is_sender_newcomer", json.bool(session.is_sender_newcomer)),
    #("is_sender_non_member", json.bool(session.is_sender_non_member())),
    #("is_sender_a_chat", json.bool(session.is_sender_a_chat)),
    #("is_message_a_comment", json.bool(session.is_message_a_comment)),
    #("real_sender", json.string(session.real_sender |> string.inspect)),
  ])
}

pub fn default() {
  BotSession(
    chat_settings: chat_settings.default(),
    user_chat: None,
    is_trusted_sender: False,
    is_admin: False,
    is_private_chat: False,
    // dependencies: Deps(
    //   cas_check: fn(_) {
    //     panic as "ERR: cas_check was not injected! Some shit happened"
    //   },
    //   db:,
    //   resources: Resources(female_names: [], unicode_script_extensions: []),
    // ),
    real_sender: #(0, None),
    is_sender_newcomer: False,
    is_sender_non_member: fn() { False },
    is_sender_a_chat: False,
    is_message_a_comment: False,
  )
}
