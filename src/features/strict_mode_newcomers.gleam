import gleam/bool
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import infra/storage/user_chat as uc_repo
import infra/strict
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.handle_number_and_reply(
    ctx,
    cmd,
    ["strict_mode_newcomers"],
    fn(cs) { cs.strict_mode_newcomers },
    "Success: strict mode (no media, links, reactions, female name) for first {0} message(s) is enabled",
    "Success: strict mode for newcomers disabled",
    "Usage: /strictModeNewcomers <no_of_msgs>",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(
    ctx.session.chat_settings.strict_mode_newcomers <= 0,
    next,
  )
  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: False,
    newcomers: True,
    chatsenders: False,
    next:,
  )

  use message <- handle.msg(upd, next)

  handle.real_sender(
    message,
    fn(from) { handle_user(ctx, next, message, from) },
    fn(_sc) {
      //chat cannot be a newcomer because there's no event to this 
      //todo think about workaround 
      next()
    },
    next,
  )
}

fn handle_user(
  ctx: BotContext,
  next: fn() -> Nil,
  message: types.Message,
  from: types.User,
) -> Nil {
  use uc <- handle.userchat(ctx, next)

  //use <- bool.lazy_guard(!uc.on_quarantine, next)

  let enough_messages =
    list.length(uc.messages) >= ctx.session.chat_settings.strict_mode_newcomers

  use <- bool.lazy_guard(enough_messages, fn() {
    uc_repo.save_user_chat_property(
      ctx.session.db,
      from.id,
      message.chat.id,
      ["on_quarantine"],
      json.bool(False),
    )
    |> result.map(fn(found_and_updated) {
      case found_and_updated {
        True -> "Ctx: {0} User {1} has passed quarantine"
        False ->
          "Ctx: {0} User {1} has passed quarantine, "
          <> "but coudn't find his user_chat entry. Some shit may happen."
      }
      |> log.printf([
        helpers.view_chat(message.chat),
        handle.view_sender(message),
      ])
    })
    |> result.lazy_unwrap(next)
  })

  let has_restricted = strict.has_suspicious_content(message)
  let has_changed_name =
    uc.first_name != from.first_name
    || uc.last_name != option.unwrap(from.last_name, "")

  use <- bool.lazy_guard(!has_restricted && !has_changed_name, next)

  let _ =
    uc_repo.delete_user_chat(ctx.session.db, from.id, message.chat.id)
    |> result.map(fn(res) {
      case res {
        True -> "Ctx: {0} Ban user {1} reason: did not passed quarantine ({2})."
        False ->
          "Ctx: {0} Ban user {1} reason: did not passed quarantine ({2}), "
          <> "but coudn't find his user_chat entry. Some shit may happen."
      }
      |> log.printf([
        helpers.view_chat(message.chat),
        helpers.view_user(from),
        case has_restricted, has_changed_name {
          True, True -> "restricted msg + changed name"
          True, False -> "restricted msg"
          False, True -> "changed name"
          _, _ -> ""
        },
      ])
    })
    |> result.try(fn(_) { api_calls.get_rid_of_msg(ctx, message.message_id) })
    |> result.try(fn(_) { api_calls.get_rid_of_usersender(ctx, from.id) })

  Nil
}
