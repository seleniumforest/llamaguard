import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/model/types.{type ChatMemberLeft}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  helpers.flip_bool_setting_and_reply(
    ctx,
    ["strict_mode_nonmembers"],
    fn(cs) { cs.strict_mode_nonmembers },
    "Success: strict mode (no media, links, reactions, female name) for non-members enabled",
    "Success: strict mode for non-members disabled",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(
    !ctx.session.chat_settings.strict_mode_nonmembers,
    fn() { next(ctx, upd) },
  )
  case upd {
    update.TextUpdate(message:, ..)
    | update.AudioUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.MessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      //check ONLY COMMENTS to posts on linked channel
      use <- bool.lazy_guard(!helpers.is_forwarded_msg(message), fn() {
        next(ctx, upd)
      })

      handle_message(ctx, upd, message, next)
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    update.MessageReactionUpdate(message_reaction_updated:, ..) ->
      //check REACTIONS from ALL users
      handle_reaction(ctx, upd, message_reaction_updated, next)
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    _ -> next(ctx, upd)
  }
}

fn handle_message(
  ctx: BotContext,
  upd: Update,
  message: types.Message,
  next: fn(BotContext, Update) -> Nil,
) {
  case message.sender_chat {
    Some(sc) -> {
      log.printf(
        "Ctx: {0} Delete message from {1} reason: hiding under chat's account",
        [helpers.view_chat(message.chat), helpers.view_chat(sc)],
      )

      api_calls.get_rid_of_msg(ctx, message.message_id)
      |> result.try(fn(_) { api_calls.get_rid_of_chat(ctx, sc) })
      |> result.map(fn(_) { Nil })
    }
    None -> {
      use mem <- result.try(api_calls.get_chat_member(
        ctx,
        message.chat.id,
        upd.from_id,
      ))

      case mem {
        types.ChatMemberLeftChatMember(member) -> {
          let restricted = helpers.has_restricted_content(message)
          let suspicious = has_suspicious_user_profile(ctx, member)
          let is_under_chat = message.sender_chat |> option.is_some

          use <- bool.lazy_guard(
            !restricted && !suspicious && !is_under_chat,
            fn() { Ok(next(ctx, upd)) },
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
          |> result.try(fn(_) { api_calls.get_rid_of_user(ctx, member.user.id) })
          |> result.map(fn(_) { Nil })
        }
        _ -> Ok(next(ctx, upd))
      }
    }
  }
}

fn handle_reaction(
  ctx: BotContext,
  upd: Update,
  message_reaction_updated: types.MessageReactionUpdated,
  next: fn(BotContext, Update) -> Nil,
) {
  use <- bool.lazy_guard(
    message_reaction_updated.new_reaction |> list.is_empty,
    fn() { Ok(next(ctx, upd)) },
  )

  case message_reaction_updated.user, message_reaction_updated.actor_chat {
    _, Some(actor_chat) -> {
      log.printf("Ctx: {0} Ban {1} reason: anon reaction as a channel", [
        helpers.view_chat(message_reaction_updated.chat),
        helpers.view_chat(actor_chat),
      ])

      api_calls.get_rid_of_chat(ctx, actor_chat)
      |> result.map(fn(_) { Nil })
    }
    Some(user), _ -> {
      api_calls.get_chat_member(ctx, upd.chat_id, user.id)
      |> result.try(fn(x) {
        case x {
          types.ChatMemberLeftChatMember(member) -> {
            log.printf("Ctx: {0} Ban {1} reason: non-member reaction", [
              helpers.view_chat(message_reaction_updated.chat),
              helpers.view_user(member.user),
            ])

            api_calls.get_rid_of_user(ctx, member.user.id)
            |> result.map(fn(_) { Nil })
          }
          _ -> Ok(next(ctx, upd))
        }
      })
    }
    _, _ -> Ok(next(ctx, upd))
  }
}

fn has_suspicious_user_profile(ctx: BotContext, member: ChatMemberLeft) -> Bool {
  let check_username = member.user.username |> option.is_none
  let check_female_name = case ctx.session.chat_settings.check_female_name {
    False -> False
    True ->
      helpers.get_fullname(member.user)
      |> helpers.has_woman_name(ctx.session.resources.female_names, _)
  }

  let check_id = case ctx.session.chat_settings.kick_new_accounts {
    i if i > 0 -> member.user.id > i
    _ -> False
  }

  check_username || check_female_name || check_id
}
