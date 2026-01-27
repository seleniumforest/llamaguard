import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/regexp
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/api
import telega/model/types.{GetChatMemberParameters, Int}
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
    update.TextUpdate(from_id:, chat_id:, message:, ..)
    | update.AudioUpdate(from_id:, chat_id:, message:, ..)
    | update.EditedMessageUpdate(from_id:, chat_id:, message:, ..)
    | update.MessageUpdate(from_id:, chat_id:, message:, ..)
    | update.PhotoUpdate(from_id:, chat_id:, message:, ..)
    | update.VideoUpdate(from_id:, chat_id:, message:, ..)
    | update.VoiceUpdate(from_id:, chat_id:, message:, ..) -> {
      let is_forward =
        message.reply_to_message
        |> option.map(fn(rtm) { rtm.is_automatic_forward })
        |> option.flatten
        |> option.unwrap(False)

      use <- bool.lazy_guard(!is_forward, fn() { next(ctx, upd) })

      api.get_chat_member(
        ctx.config.api_client,
        GetChatMemberParameters(chat_id: Int(chat_id), user_id: from_id),
      )
      |> result.try(fn(mem) {
        case mem {
          types.ChatMemberLeftChatMember(member) -> {
            let restricted = has_restricted_content(message)
            let suspicious = has_suspicious_profile(ctx, member)

            use <- bool.lazy_guard(!restricted && !suspicious, fn() {
              Ok(next(ctx, upd))
            })

            let reason = case restricted, suspicious {
              True, True -> "restricted and suspicious profile"
              True, False -> "restricted"
              False, True -> "suspicious profile"
              _, _ -> ""
            }

            log.printf("Ban user: {0} {1} id: {2} reason: {3}", [
              member.user.first_name,
              member.user.last_name |> option.unwrap(""),
              member.user.id |> int.to_string,
              reason,
            ])

            api.delete_message(
              ctx.config.api_client,
              types.DeleteMessageParameters(
                chat_id: Int(chat_id),
                message_id: message.message_id,
              ),
            )
            |> result.map(fn(_) { Nil })
          }
          _ -> Ok(next(ctx, upd))
        }
      })
      |> result.map_error(fn(err) {
        log.print_err(err |> string.inspect)
        err
      })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
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
