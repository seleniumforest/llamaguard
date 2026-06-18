import gleam/bool
import gleam/option
import gleam/result
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
    ["cas_enabled"],
    fn(cs) { cs.cas_enabled },
    "Success: bot will use Combot's anti-spam lists for joining users and linked channel's comments",
    "Success: bot won't use Combot's anti-spam lists anymore",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(!ctx.session.chat_settings.cas_enabled, fn() {
    next(ctx, upd)
  })

  case upd {
    update.ChatMemberUpdate(chat_member_updated:, ..) -> {
      check_and_reply(
        ctx,
        upd,
        next,
        chat_member_updated.chat,
        chat_member_updated.from,
      )
    }
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      case message.from {
        option.None -> next(ctx, upd)
        option.Some(from) -> {
          //todo check all later with caching/export
          // case from.id == 777_000 {
          //   True -> check_and_reply(ctx, upd, next, message.chat, from)
          //   False -> next(ctx, upd)
          // }
          check_and_reply(ctx, upd, next, message.chat, from)
        }
      }
    }
    _ -> next(ctx, upd)
  }
}

fn check_and_reply(
  ctx: BotContext,
  upd,
  next,
  chat: types.Chat,
  from: types.User,
) {
  let is_cas_banned = ctx.session.dependencies.cas_check(from.id)
  use <- bool.lazy_guard(!is_cas_banned, fn() { next(ctx, upd) })

  log.printf("Ctx: {0} Ban {1} reason: CAS", [
    helpers.view_chat(chat),
    helpers.view_user(from),
  ])

  api_calls.get_rid_of_user(ctx, from.id)
  |> result.try(fn(_) { Ok(Nil) })
  |> result.lazy_unwrap(fn() { next(ctx, upd) })
}
