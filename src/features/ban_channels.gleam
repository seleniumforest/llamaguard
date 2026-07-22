import gleam/bool
import gleam/int
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cache_validation
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  let #(new_ctx, errors) =
    cache_validation.validate_one(ctx, cache_validation.validate_linked_channel)

  case errors == [] {
    True ->
      cmd_utils.flip_bool_setting_and_reply(
        new_ctx,
        ["ban_channels"],
        fn(cs) { cs.ban_channels },
        "Success: sending messages on behalf of a channel restricted",
        "Success: sending messages on behalf of a channel allowed",
      )
    False -> {
      log.printf(
        "chat_id:{0} cmd:{1} errors:{2} couldnt validate linked channel",
        [
          ctx.update.chat_id |> int.to_string,
          cmd.text,
          errors |> string.inspect,
        ],
      )

      cmd_utils.flip_bool_setting_and_reply(
        new_ctx,
        ["ban_channels"],
        fn(cs) { cs.ban_channels },
        "Success: sending messages on behalf of a channel restricted, "
          <> "but i couldn't get fresh info about linked channel. "
          <> "If you want to send messages on behalf of a channel, "
          <> "please use /trustuser @yourchannel manually to trust it.",
        "Success: sending messages on behalf of a channel allowed with errors",
      )
    }
  }
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(!ctx.session.chat_settings.ban_channels, next)
  // use <- handle.apply_to_targets(
  //   session: ctx.session,
  //   trusted_senders: False,
  //   non_members: False,
  //   newcomers: False,
  //   chatsenders: True,
  //   next:,
  // )

  use message <- handle.msg(upd, next)
  handle.real_sender(
    message,
    fn(_) { next() },
    fn(sc) {
      use <- bool.lazy_guard(ctx.session.is_trusted_sender, next)

      log.printf(
        "Ctx: {0} Ban {1} reason: restricted sending on behalf of a chat",
        [helpers.view_chat(message.chat), helpers.view_chat(sc)],
      )

      api_calls.get_rid_of_msg(ctx, message.message_id)
      |> result.try(fn(_) { api_calls.get_rid_of_chatsender(ctx, sc) })
      |> result.try(fn(_) { Ok(Nil) })
      |> result.lazy_unwrap(next)
    },
    next,
  )
}
