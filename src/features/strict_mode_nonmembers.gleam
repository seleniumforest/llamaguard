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
      //check REACTIONS from ALL users
      handle_reaction(ctx, upd, message_reaction_updated, next)
      |> result.lazy_unwrap(next)
    },
    next,
  )
}

fn handle_message(ctx: BotContext, message: types.Message, next: fn() -> Nil) {
  handle.real_sender(
    message,
    fn(user) {
      use mem <- result.try(api_calls.get_chat_member(
        ctx,
        message.chat.id,
        user.id,
      ))

      case mem {
        types.ChatMemberLeftChatMember(member) -> {
          let restricted = strict.has_suspicious_content(message)
          let suspicious = has_suspicious_user_profile(ctx, member)
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

          log.printf("Ctx: {0} Ban user {1} reason: {2}", [
            helpers.view_chat(message.chat),
            helpers.view_user(member.user),
            reason,
          ])

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
        "Ctx: {0} Delete message from {1} reason: hiding under chat's account",
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
  //idk, should we handle also chats here
  case message_reaction_updated.user, message_reaction_updated.actor_chat {
    _, Some(actor_chat) -> {
      log.printf("Ctx: {0} Ban {1} reason: anon reaction as a channel", [
        helpers.view_chat(message_reaction_updated.chat),
        helpers.view_chat(actor_chat),
      ])

      // TelegramApiError(400, "Bad Request: invalid user_id specified")
      // message_reaction_updated.new_reaction
      // |> list.try_each(fn(x) {
      //   api_calls.get_rid_of_reaction(
      //     ctx,
      //     message_reaction_updated.chat.id,
      //     message_reaction_updated.message_id,
      //     actor_chat.id,
      //     x,
      //   )
      // })
      // |> result.try(fn(_) { api_calls.get_rid_of_chatsender(ctx, actor_chat) })

      api_calls.get_rid_of_chatsender(ctx, actor_chat)
      |> result.try(fn(_) { Ok(Nil) })
    }
    Some(user), _ -> {
      use mem <- result.try(api_calls.get_chat_member(ctx, upd.chat_id, user.id))
      case mem {
        types.ChatMemberLeftChatMember(member) -> {
          log.printf("Ctx: {0} Ban {1} reason: non-member reaction", [
            helpers.view_chat(message_reaction_updated.chat),
            helpers.view_user(member.user),
          ])

          message_reaction_updated.new_reaction
          |> list.try_each(fn(x) {
            api_calls.get_rid_of_reaction(
              ctx,
              message_reaction_updated.chat.id,
              message_reaction_updated.message_id,
              user.id,
              x,
            )
          })
          |> result.try(fn(_) {
            api_calls.get_rid_of_usersender(ctx, member.user.id)
          })
          |> result.try(fn(_) { Ok(Nil) })
        }
        _ -> Ok(next())
      }
    }
    _, _ -> Ok(next())
  }
}

fn has_suspicious_user_profile(ctx: BotContext, member: ChatMemberLeft) -> Bool {
  let check_username = member.user.username |> option.is_none
  let check_female_name = case ctx.session.chat_settings.check_female_name {
    False -> False
    True ->
      helpers.get_fullname(member.user)
      |> strict.has_woman_name(ctx.session.resources.female_names, _)
  }

  let check_id = case ctx.session.chat_settings.kick_new_accounts {
    i if i > 0 -> member.user.id > i
    _ -> False
  }

  check_username || check_female_name || check_id
}
