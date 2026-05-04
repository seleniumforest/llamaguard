import gleam/bool
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  helpers.flip_bool_setting_and_reply(
    ctx,
    ["ban_channels"],
    fn(cs) { cs.ban_channels },
    "Success: sending messages on behalf of a channel was restricted",
    "Success: sending messages on behalf of a channel was allowed",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(!ctx.session.chat_settings.ban_channels, fn() {
    next(ctx, upd)
  })

  case upd {
    update.TextUpdate(message:, ..)
    | update.AudioUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.MessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      case message.sender_chat {
        Some(sc) -> {
          use <- bool.lazy_guard(
            helpers.is_trusted(
              ctx.session.chat_settings.trusted_users,
              sc.id,
              sc.username,
            ),
            fn() { next(ctx, upd) },
          )

          log.printf(
            "Ctx: {0} Ban {1} reason: restricted sending on behalf of a chat",
            [helpers.view_chat(message.chat), helpers.view_chat(sc)],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) { api_calls.get_rid_of_chat(ctx, sc) })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(fn() { next(ctx, upd) })
        }
        None -> next(ctx, upd)
      }
    }
    _ -> next(ctx, upd)
  }
}
