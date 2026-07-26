import gleam/bool
import gleam/list
import gleam/option.{Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import infra/strict
import models/error.{type BotError}
import telega/model/types.{type ChatMemberLeft}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.flip_bool_setting_and_reply(
    ctx,
    ["strict_mode_nonmembers"],
    fn(cs) { cs.strict_mode_nonmembers },
    "Success: strict mode for non-members enabled",
    "Success: strict mode for non-members disabled",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  let next = fn() { next(ctx, upd) }

  use <- bool.lazy_guard(
    !ctx.session.chat_settings.strict_mode_nonmembers,
    next,
  )

  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: True,
    newcomers: False,
    chatsenders: True,
    next:,
  )

  handle.upd(
    upd,
    fn(message) {
      //check ONLY COMMENTS to posts on linked channel
      use <- bool.lazy_guard(!helpers.is_forwarded_msg(message), next)

      handle_message(ctx, message, next)
      |> result.lazy_unwrap(next)
    },
    fn(_join) { next() },
    fn(message_reaction_updated) {
      //kinda dont know, how to treat channels here, should they be as "non-member" or not?
      handle_reaction(ctx, upd, message_reaction_updated, next)
      |> result.lazy_unwrap(next)
      next()
    },
    next,
  )
}

fn handle_message(ctx: BotContext, message: types.Message, next: fn() -> Nil) {
  handle.real_sender(
    message,
    fn(user) {
      use mem <- result.try(helpers.get_chat_member_cached(
        ctx,
        message.chat.id,
        user.id,
      ))

      case mem {
        types.ChatMemberLeftChatMember(member) -> {
          let restricted = strict.has_suspicious_content(message)
          let suspicious = has_suspicious_user_profile(member)
          let is_under_chat = message.sender_chat |> option.is_some

          use <- bool.lazy_guard(
            !restricted && !suspicious && !is_under_chat,
            fn() { Ok(next()) },
          )

          let reason = case restricted, suspicious {
            True, True -> "restricted message and suspicious profile"
            True, False -> "restricted message"
            False, True -> "suspicious profile"
            _, _ -> ""
          }

          log.printf(
            "Ctx: {0} Ban {1} Filter: strict_mode_nonmembers Reason: {2}",
            [
              helpers.view_chat(message.chat),
              helpers.view_user(member.user),
              reason,
            ],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_usersender(ctx, member.user.id)
          })
          |> result.map(fn(_) { Nil })
        }
        _ -> Ok(next())
      }
    },
    fn(sc) {
      log.printf(
        "Ctx: {0} Ban {1} Filter: strict_mode_nonmembers Reason: hiding under chat's account",
        [helpers.view_chat(message.chat), helpers.view_chat(sc)],
      )

      api_calls.get_rid_of_msg(ctx, message.message_id)
      |> result.try(fn(_) { api_calls.get_rid_of_chatsender(ctx, sc) })
      |> result.map(fn(_) { Nil })
    },
    fn() { Ok(next()) },
  )
}

pub fn handle_reaction(
  ctx: BotContext,
  upd: Update,
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
      use mem <- result.try(helpers.get_chat_member_cached(
        ctx,
        upd.chat_id,
        user.id,
      ))
      case mem {
        types.ChatMemberLeftChatMember(member) -> {
          log.printf(
            "Ctx: {0} Ban {1} Filter: strict_mode_nonmembers Reason: non-member reaction",
            [
              helpers.view_chat(message_reaction_updated.chat),
              helpers.view_user(member.user),
            ],
          )

          api_calls.get_rid_of_usersender(ctx, user.id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_usersender_reactions(
              ctx,
              message_reaction_updated.chat.id,
              user.id,
            )
          })
          |> result.try(fn(_) { Ok(Nil) })
        }
        _ -> Ok(next())
      }
    },
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
    },
    fn() { Ok(next()) },
  )
}

fn has_suspicious_user_profile(member: ChatMemberLeft) -> Bool {
  let check_username = member.user.username |> option.is_none

  check_username
}
