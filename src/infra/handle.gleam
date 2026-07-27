//everything related to determine real sender and groups 
import gleam/bool
import gleam/option.{type Option, None, Some}
import gleam/string
import infra/alias
import infra/helpers
import models/bot_session.{type BotSession}
import models/error.{type BotError, CannotFindRealSender}
import models/user_chat
import telega/model/types.{type Message}
import telega/update.{type Update}

pub fn apply_to_targets(
  session session: BotSession(a),
  trusted_senders trusted_senders: Bool,
  non_members non_members: Bool,
  newcomers newcomers: Bool,
  chatsenders chatsenders: Bool,
  next next: fn() -> Nil,
  checker handler: fn() -> Nil,
) {
  let trusted = !trusted_senders && session.is_trusted_sender
  use <- bool.lazy_guard(trusted, next)

  let newcomer = newcomers && session.is_sender_newcomer
  let chatsender = chatsenders && session.is_sender_a_chat
  case newcomer || chatsender {
    True -> handler()
    False -> {
      let non_member = non_members && session.is_sender_non_member()
      case non_member {
        True -> handler()
        False -> next()
      }
    }
  }
}

pub fn get_real_sender_by_upd(
  update: Update,
) -> Result(#(Int, Option(String)), BotError) {
  upd(
    update,
    fn(message) {
      real_sender(
        message,
        fn(from) { Ok(#(from.id, from.username)) },
        fn(sc) { Ok(#(sc.id, sc.username)) },
        fn() { Error(CannotFindRealSender) },
      )
    },
    fn(chat_member_updated) {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(m) -> #(m.user.id, m.user.username)
        types.ChatMemberLeftChatMember(l) -> #(l.user.id, l.user.username)
        _ -> #(chat_member_updated.from.id, chat_member_updated.from.username)
      }
      |> Ok
    },
    fn(message_reaction_updated) {
      reaction_sender(
        message_reaction_updated,
        fn(user) { #(user.id, user.username) },
        fn(sc) { #(sc.id, sc.username) },
        fn() { #(update.from_id, option.None) },
      )
      |> Ok
    },
    fn() { Ok(#(update.from_id, option.None)) },
  )
}

pub fn upd(
  upd: Update,
  on_message: fn(types.Message) -> a,
  on_member_upd: fn(types.ChatMemberUpdated) -> a,
  on_reaction: fn(types.MessageReactionUpdated) -> a,
  fallback: fn() -> a,
) {
  case upd {
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..)
    | update.MessageUpdate(message:, ..) -> on_message(message)
    update.ChatMemberUpdate(chat_member_updated:, ..) ->
      on_member_upd(chat_member_updated)
    update.MessageReactionUpdate(message_reaction_updated:, ..) ->
      on_reaction(message_reaction_updated)
    _ -> fallback()
  }
}

pub fn joined_user(
  chat_member_updated: types.ChatMemberUpdated,
  fallback: fn() -> a,
  continuation: fn(types.User) -> a,
) {
  case
    chat_member_updated.old_chat_member,
    chat_member_updated.new_chat_member
  {
    types.ChatMemberRestrictedChatMember(_), types.ChatMemberMemberChatMember(m)
    | types.ChatMemberLeftChatMember(_), types.ChatMemberMemberChatMember(m)
    | types.ChatMemberBannedChatMember(_), types.ChatMemberMemberChatMember(m)
    -> {
      continuation(m.user)
    }
    _, _ -> fallback()
  }
}

pub fn msg(
  update: update.Update,
  fallback: fn() -> a,
  has_msg: fn(Message) -> a,
) {
  upd(update, has_msg, fn(_) { fallback() }, fn(_) { fallback() }, fallback)
}

pub fn member_upd(
  update: update.Update,
  fallback: fn() -> a,
  mem_upd: fn(types.ChatMemberUpdated) -> a,
) {
  upd(update, fn(_) { fallback() }, mem_upd, fn(_) { fallback() }, fallback)
}

pub fn memberupd_and_reaction(
  update: Update,
  on_member_upd: fn(types.ChatMemberUpdated) -> a,
  on_reaction: fn(types.MessageReactionUpdated) -> a,
  fallback: fn() -> a,
) {
  upd(update, fn(_msg) { fallback() }, on_member_upd, on_reaction, fallback)
}

pub fn reaction_sender(
  reaction: types.MessageReactionUpdated,
  on_user: fn(types.User) -> a,
  on_channel: fn(types.Chat) -> a,
  fallback: fn() -> a,
) {
  case reaction.user, reaction.actor_chat {
    Some(user), _ -> on_user(user)
    _, Some(chat) -> on_channel(chat)
    _, _ -> fallback()
  }
}

pub fn userchat(
  ctx: alias.BotContext,
  fallback: fn() -> a,
  has_uc: fn(user_chat.UserChat) -> a,
) {
  let userchat = ctx.session.user_chat
  case userchat {
    Some(uc) -> has_uc(uc)
    None -> fallback()
  }
}

pub fn real_sender(
  msg: Message,
  on_user: fn(types.User) -> a,
  on_channel: fn(types.Chat) -> a,
  fallback: fn() -> a,
) {
  case msg.guest_bot_caller_user, msg.sender_chat, msg.from {
    Some(caller), _, _ -> on_user(caller)
    _, Some(sc), Some(from) if from.id == 777_000 || from.id == 136_817_688 ->
      on_channel(sc)
    _, None, Some(from) -> on_user(from)
    _, Some(sc), None -> on_channel(sc)
    _, _, _ -> fallback()
  }
}

pub fn view_sender(msg: Message) {
  real_sender(msg, helpers.view_user, helpers.view_chat, fn() { "<no sender>" })
}

pub fn get_visible_text(msg: Message) {
  let title =
    real_sender(
      msg,
      helpers.get_fullname,
      fn(chat) { chat.title |> option.unwrap("") },
      fn() { "" },
    )

  string.join(
    [msg.text |> option.unwrap(""), msg.caption |> option.unwrap(""), title],
    " ",
  )
  |> string.trim
}
