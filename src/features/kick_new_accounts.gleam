import gleam/bool
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.handle_number_and_reply(
    ctx,
    cmd,
    ["kick_new_accounts"],
    fn(cs) { cs.kick_new_accounts },
    "Success: joining users with telegram id over {0} will be kicked.",
    "Success: joining users with telegram id over {0} will NOT be kicked anymore.",
    "Usage: /kickNewAccounts <id_to_kick>",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  log.debug(ctx.dependencies.log, "kick_new_accounts")
  let next = fn() { next(ctx, upd) }
  let ids_to_delete = ctx.session.chat_settings.kick_new_accounts
  use <- bool.lazy_guard(ids_to_delete <= 0, next)

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
    fn(_message) { next() },
    fn(chat_member_updated) {
      use member <- handle.joined_user(chat_member_updated, next)
      let needs_ban = member.id > ids_to_delete && !member.is_bot
      use <- bool.lazy_guard(!needs_ban, next)

      log.printf(
        "Ctx: {0} Ban {1} Filter: kick_new_accounts Reason: msg from fresh account",
        [
          helpers.view_chat(chat_member_updated.chat),
          helpers.view_user(chat_member_updated.from),
        ],
      )

      api_calls.get_rid_of_usersender(ctx, member.id)
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(next)
    },
    fn(reaction) {
      handle.reaction_sender(
        reaction,
        fn(user) {
          let needs_ban = user.id > ids_to_delete && !user.is_bot
          use <- bool.lazy_guard(!needs_ban, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: kick_new_accounts Reason: reaction from fresh account",
            [
              helpers.view_chat(reaction.chat),
              helpers.view_user(user),
            ],
          )

          api_calls.get_rid_of_usersender(ctx, user.id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_usersender_reactions(
              ctx,
              reaction.chat.id,
              user.id,
            )
          })
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        },
        fn(_) { next() },
        next,
      )
    },
    next,
  )
}
