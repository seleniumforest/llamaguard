import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import infra/reply.{reply, replyf}
import infra/storage.{Value}
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update, ChatMemberUpdate}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  let cmd_args =
    cmd.text
    |> string.split(" ")
    |> list.rest()
    |> result.unwrap([])
    |> list.filter(fn(x) { x |> string.is_empty |> bool.negate })

  let args_count = cmd_args |> list.length
  let first_arg =
    cmd_args
    |> list.first()
    |> result.unwrap("")
    |> int.parse()

  case first_arg {
    Error(_) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      case current_state, args_count {
        //when user has enabled kick_new_accounts feature, and provides no arguments
        cs, ac if cs > 0 && ac == 0 -> {
          let new_state = 0
          set_state(ctx, current_state, new_state)
        }
        _, _ -> reply(ctx, "Usage: /kickNewAccounts <id_to_kick>")
      }
    }
    Ok(num) -> {
      let current_state = ctx.session.chat_settings.kick_new_accounts
      let new_state = num

      set_state(ctx, current_state, new_state)
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

fn set_state(ctx: BotContext, current_state: Int, new_state: Int) {
  storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "kick_new_accounts",
    Value(storage.Int(new_state)),
  )
  |> result.try(fn(_) {
    case new_state {
      ns if ns > 0 ->
        replyf(
          ctx,
          "Success: joining users with telegram id over {0} will be kicked",
          [new_state |> int.to_string()],
        )
      _ ->
        replyf(
          ctx,
          "Success: joining users with telegram id over {0} will NOT be kicked",
          [current_state |> int.to_string()],
        )
    }
  })
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  let ids_to_delete = ctx.session.chat_settings.kick_new_accounts

  case upd, ids_to_delete {
    ChatMemberUpdate(chat_member_updated:, ..), itd if itd > 0 -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          let needs_ban = member.user.id > ids_to_delete && !member.user.is_bot
          use <- bool.lazy_guard(!needs_ban, fn() { next(ctx, upd) })

          log.printf("Ban user: {0} id: {1} reason: fresh account", [
            helpers.get_fullname(member.user),
            int.to_string(member.user.id),
          ])

          api_calls.get_rid_of_user(ctx, member.user.id)
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(fn() { next(ctx, upd) })
        }
        _ -> next(ctx, upd)
      }
    }

    _, _ -> next(ctx, upd)
  }
}
