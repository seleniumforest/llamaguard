import gleam/bool
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
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
  log.debug(ctx.dependencies.log, "strict_mode_newcomers")
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

  handle.upd(
    upd,
    fn(message) {
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
    },
    fn(chat_member_updated) {
      use user <- handle.joined_user(chat_member_updated, next)
      let empty_username = user.username |> option.is_none

      use <- bool.lazy_guard(!empty_username, next)

      log.printf(
        "Ctx: {0} Ban {1} Filter: strict_mode_newcomers Reason: empty username",
        [
          helpers.view_chat(chat_member_updated.chat),
          helpers.view_user(user),
        ],
      )

      api_calls.get_rid_of_usersender(ctx, user.id)
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(next)
    },
    fn(reaction) {
      handle_reaction(ctx, upd, reaction, next) |> result.lazy_unwrap(next)
    },
    next,
  )
}

pub fn handle_reaction(
  ctx: BotContext,
  _upd: Update,
  message_reaction_updated: types.MessageReactionUpdated,
  next: fn() -> Nil,
) {
  use <- bool.lazy_guard(
    message_reaction_updated.new_reaction |> list.is_empty,
    fn() { Ok(next()) },
  )

  handle.reaction_sender(
    message_reaction_updated,
    fn(user) {
      log.printf(
        "Ctx: {0} Delete reaction {1} Filter: strict_mode_newcomers Reason: newcomer reaction",
        [
          helpers.view_chat(message_reaction_updated.chat),
          helpers.view_user(user),
        ],
      )

      // just for a test, maybe we can count these reactions and ban after threshold

      // api_calls.get_rid_of_usersender(ctx, user.id)
      // |> result.try(fn(_) {
      //   api_calls.get_rid_of_usersender_reactions(
      //     ctx,
      //     message_reaction_updated.chat.id,
      //     user.id,
      //   )
      // })

      api_calls.get_rid_of_usersender_reactions(
        ctx,
        message_reaction_updated.chat.id,
        user.id,
      )
      |> result.try(fn(_) { Ok(Nil) })
    },
    fn(_actor_chat) { Ok(next()) },
    fn() { Ok(next()) },
  )
}

fn handle_user(
  ctx: BotContext,
  next: fn() -> Nil,
  message: types.Message,
  from: types.User,
) -> Nil {
  use uc <- handle.userchat(ctx, next)

  let has_restricted = strict.has_suspicious_content(message)
  let has_changed_name =
    uc.first_name != from.first_name
    || uc.last_name != option.unwrap(from.last_name, "")

  let unique_msgs = uc.messages |> list.map(fn(m) { m.text }) |> list.unique
  let has_similar_messages =
    !list.is_empty(uc.messages)
    && list.length(unique_msgs) < list.length(uc.messages)

  let enough_messages =
    list.length(uc.messages) >= ctx.session.chat_settings.strict_mode_newcomers

  case
    has_restricted || has_changed_name || has_similar_messages,
    enough_messages
  {
    True, _ -> {
      let _ =
        uc_repo.set_user_banned(ctx.dependencies.db, from.id, message.chat.id)
        |> result.map(fn(res) {
          case res {
            True ->
              "Ctx: {0} Ban {1} Filter: strict_mode_newcomers Reason: did not passed quarantine. "
              <> "has_restricted, has_changed_name, has_similar_messages = {2}"
            False ->
              "Ctx: {0} Ban {1} Filter: strict_mode_newcomers Reason: did not passed quarantine, "
              <> "has_restricted, has_changed_name, has_similar_messages = {2}, "
              <> "but coudn't find his user_chat entry. Some shit may happen."
          }
          |> log.printf([
            helpers.view_chat(message.chat),
            helpers.view_user(from),
            string.inspect(#(
              has_restricted,
              has_changed_name,
              has_similar_messages,
            )),
          ])
        })
        |> result.try(fn(_) {
          api_calls.get_rid_of_msg(ctx, message.message_id)
        })
        |> result.try(fn(_) { api_calls.get_rid_of_usersender(ctx, from.id) })

      Nil
    }
    False, True -> {
      uc_repo.save_user_chat_property(
        ctx.dependencies.db,
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
    }
    _, _ -> next()
  }
}
