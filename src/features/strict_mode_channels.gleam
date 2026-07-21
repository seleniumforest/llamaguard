import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import infra/strict
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.flip_bool_setting_and_reply(
    ctx,
    ["strict_mode_channels"],
    fn(cs) { cs.strict_mode_channels },
    "Success: strict mode for channels enabled",
    "Success: strict mode for channels disabled",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(!ctx.session.chat_settings.strict_mode_channels, next)
  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: False,
    newcomers: False,
    chatsenders: True,
    next:,
  )

  handle.upd(
    upd,
    fn(message) {
      handle.real_sender(
        message,
        fn(_user) { next() },
        fn(channel) {
          let has_sus_content = strict.has_suspicious_content(message)
          use <- bool.lazy_guard(!has_sus_content, next)

          log.printf(
            "Ctx: {0} Delete message from {1} reason: posts sus content under chat's account",
            [helpers.view_chat(message.chat), helpers.view_chat(channel)],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) { api_calls.get_rid_of_chatsender(ctx, channel) })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        next,
      )
    },
    fn(_join) {
      //there's no join event for channels
      next()
    },
    fn(message_reaction_updated) {
      use <- bool.lazy_guard(
        message_reaction_updated.new_reaction |> list.is_empty,
        next,
      )

      let current_chat = message_reaction_updated.chat
      case message_reaction_updated.actor_chat {
        Some(actor_chat) -> {
          log.printf(
            "Ctx: {0} Ban {1} reason: anon reaction as a channel (strict mode)",
            [
              helpers.view_chat(current_chat),
              helpers.view_chat(actor_chat),
            ],
          )

          message_reaction_updated.new_reaction
          |> list.try_each(fn(reaction) {
            api_calls.get_rid_of_reaction(
              ctx,
              current_chat.id,
              message_reaction_updated.message_id,
              actor_chat.id,
              reaction,
            )
          })
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender(ctx, actor_chat)
          })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        }
        None -> next()
      }
    },
    next,
  )
}
