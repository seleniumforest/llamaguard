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
    fn(_message) {
      //todo
      next()
    },
    fn(chat_member_updated) {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          let needs_ban = member.user.id > ids_to_delete && !member.user.is_bot
          use <- bool.lazy_guard(!needs_ban, next)

          log.printf("Ctx: {0} Ban {1} reason: fresh account", [
            helpers.view_chat(chat_member_updated.chat),
            helpers.view_user(chat_member_updated.from),
          ])

          api_calls.get_rid_of_usersender(ctx, member.user.id)
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        }
        _ -> next()
      }
    },
    fn(_reaction) {
      //todo
      next()
    },
    next,
  )
}
