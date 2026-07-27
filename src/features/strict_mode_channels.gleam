import gleam/bool
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
  log.debug(ctx.dependencies.log, "strict_mode_channels")
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
            "Ctx: {0} Ban {1} Filter: strict_mode_channels Reason: posts sus content under chat's account",
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
      //soft assert just for the case
      use <- bool.lazy_guard(!ctx.session.is_sender_a_chat, next)

      handle.reaction_sender(
        message_reaction_updated,
        fn(_) { next() },
        fn(actor_chat) {
          log.printf(
            "Ctx: {0} Ban {1} Filter: strict_mode_nonmembers Reason: anon reaction as a channel",
            [
              helpers.view_chat(message_reaction_updated.chat),
              helpers.view_chat(actor_chat),
            ],
          )

          api_calls.get_rid_of_chatsender(ctx, actor_chat)
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender_reactions(
              ctx,
              message_reaction_updated.chat.id,
              actor_chat.id,
            )
          })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        next,
      )

      next()
    },
    next,
  )
}
