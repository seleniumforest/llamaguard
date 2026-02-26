import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  helpers.flip_bool_setting_and_reply(
    ctx,
    "strict_mode_nonmembers",
    fn(cs) { cs.strict_mode_nonmembers },
    "Success: strict mode (no media, links, reactions, female name) for non-members enabled",
    "Success: strict mode for non-members disabled",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(
    !ctx.session.chat_settings.strict_mode_nonmembers,
    fn() { next(ctx, upd) },
  )
  case upd {
    update.TextUpdate(message:, ..)
    | update.AudioUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.MessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      handle_message(ctx, upd, message, next)
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    update.MessageReactionUpdate(message_reaction_updated:, ..) ->
      handle_reaction(ctx, upd, message_reaction_updated, next)
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    _ -> next(ctx, upd)
  }
}

fn handle_message(
  ctx: BotContext,
  upd: Update,
  message: types.Message,
  next: fn(BotContext, Update) -> Nil,
) {
  api_calls.get_chat_member(ctx, message.chat.id, upd.from_id)
  |> result.try(fn(mem) {
    case mem {
      types.ChatMemberLeftChatMember(member) -> {
        let restricted = has_restricted_content(message)
        let suspicious = has_suspicious_profile(ctx, member)
        let is_under_chat = message.sender_chat |> option.is_some

        use <- bool.lazy_guard(
          !restricted && !suspicious && !is_under_chat,
          fn() { Ok(next(ctx, upd)) },
        )

        case message.sender_chat {
          Some(chat) -> {
            log.printf("Delete message from chat: {0} id: {1} reason: {2}", [
              chat.title |> option.unwrap(""),
              chat.id |> int.to_string,
              "hiding under chat's account",
            ])

            api_calls.get_rid_of_msg(ctx, message.message_id)
            |> result.map(fn(_) { api_calls.get_rid_of_chat(ctx, chat) })
            |> result.flatten
          }
          None -> {
            let reason = case restricted, suspicious {
              True, True -> "restricted message and suspicious profile"
              True, False -> "restricted message"
              False, True -> "suspicious profile"
              _, _ -> ""
            }

            log.printf("Delete message from user: {0} id: {1} reason: {2}", [
              helpers.try_get_fullname(message.from),
              member.user.id |> int.to_string,
              reason,
            ])

            api_calls.get_rid_of_msg(ctx, message.message_id)
            |> result.map(fn(_) {
              api_calls.get_rid_of_user(ctx, member.user.id)
            })
            |> result.flatten
          }
        }
        |> result.map(fn(_) { Nil })
      }
      _ -> Ok(next(ctx, upd))
    }
  })
}

fn handle_reaction(
  ctx: BotContext,
  upd: Update,
  message_reaction_updated: types.MessageReactionUpdated,
  next: fn(BotContext, Update) -> Nil,
) {
  use <- bool.lazy_guard(
    message_reaction_updated.new_reaction |> list.is_empty,
    fn() { Ok(next(ctx, upd)) },
  )

  case message_reaction_updated.user, message_reaction_updated.actor_chat {
    _, Some(actor_chat) -> {
      log.printf("Ban channel: {0} id: {1} reason: anon reaction as channel", [
        actor_chat.title |> option.unwrap(""),
        actor_chat.id |> int.to_string,
      ])

      api_calls.get_rid_of_chat(ctx, actor_chat)
      |> result.map(fn(_) { Nil })
    }
    Some(user), _ -> {
      api_calls.get_chat_member(ctx, upd.chat_id, user.id)
      |> result.try(fn(x) {
        case x {
          types.ChatMemberLeftChatMember(member) -> {
            log.printf("Ban user: {0} id: {1} reason: non-member reaction", [
              helpers.get_fullname(member.user),
              member.user.id |> int.to_string,
            ])

            api_calls.get_rid_of_user(ctx, member.user.id)
            |> result.map(fn(_) { Nil })
          }
          _ -> Ok(next(ctx, upd))
        }
      })
    }
    _, _ -> Ok(next(ctx, upd))
  }
}

fn has_suspicious_profile(ctx: BotContext, member: types.ChatMemberLeft) -> Bool {
  let check_username = member.user.username |> option.is_none
  let check_female_name = case ctx.session.chat_settings.check_female_name {
    False -> False
    True -> {
      let first =
        ctx.session.resources.female_names
        |> list.contains(
          member.user.first_name |> string.lowercase() |> string.trim,
        )

      let last =
        ctx.session.resources.female_names
        |> list.contains(
          member.user.last_name
          |> option.unwrap("")
          |> string.lowercase()
          |> string.trim,
        )

      first || last
    }
  }

  let check_id = case ctx.session.chat_settings.kick_new_accounts {
    i if i > 0 -> member.user.id > i
    _ -> False
  }

  check_username || check_female_name || check_id
}

fn has_restricted_content(msg: types.Message) -> Bool {
  let is_audio = msg.audio |> option.is_some
  let is_photo = msg.photo |> option.is_some
  let is_video = msg.video |> option.is_some
  let is_video_note = msg.video_note |> option.is_some
  let is_game = msg.game |> option.is_some
  let is_document = msg.document |> option.is_some
  let is_sticker = msg.sticker |> option.is_some
  let is_caption_entities =
    msg.caption_entities |> option.unwrap([]) |> list.is_empty |> bool.negate

  let has_entities =
    msg.entities |> option.unwrap([]) |> list.is_empty |> bool.negate

  let contains_link = case regexp.from_string("https?://\\S+") {
    Ok(url_regex) -> {
      regexp.scan(with: url_regex, content: msg.text |> option.unwrap(""))
      |> list.is_empty
      |> bool.negate
    }
    Error(_) -> False
  }

  is_audio
  || is_photo
  || contains_link
  || has_entities
  || is_video
  || is_video_note
  || is_game
  || is_document
  || is_sticker
  || is_caption_entities
}
