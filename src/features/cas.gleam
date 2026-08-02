import gleam/bool
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.flip_bool_setting_and_reply(
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
  log.debug(ctx.dependencies.log, "cas")
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(!ctx.session.chat_settings.cas_enabled, next)

  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: False,
    next:,
  )

  handle.upd(
    upd,
    fn(message) {
      //no need to check n times when user is on quarantine, 
      //just check once on join or when he's writing in comments
      use <- bool.lazy_guard(!ctx.session.is_message_a_comment, next)

      handle.real_sender(
        message,
        fn(from) { check_and_reply(ctx, next, message.chat, from) },
        fn(_sc) { next() },
        next,
      )
    },
    fn(chat_member_updated) {
      use member <- handle.joined_user(chat_member_updated, next)
      check_and_reply(ctx, next, chat_member_updated.chat, member)
    },
    fn(_reaction) {
      //redundant check, seems like cas db has only users who posted spam message
      next()
    },
    next,
  )
}

fn check_and_reply(ctx: BotContext, next, chat: types.Chat, from: types.User) {
  let cas_offences = ctx.dependencies.services.cas_service.cas_check(from.id)
  use <- bool.lazy_guard(result.unwrap(cas_offences, 0) <= 0, next)

  log.printf("Ctx: {0} Ban {1} Filter: cas Reason: CAS", [
    helpers.view_chat(chat),
    helpers.view_user(from),
  ])

  api_calls.get_rid_of_usersender(ctx, from.id)
  |> result.try(fn(_) { Ok(Nil) })
  |> result.lazy_unwrap(next)
}
