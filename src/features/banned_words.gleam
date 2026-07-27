import gleam/bool
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
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  let input_words =
    cmd.payload
    |> option.unwrap("")
    |> string.lowercase
    |> string.trim

  case string.is_empty(input_words) {
    True ->
      reply(ctx, "Usage: /banPhrase <phrase>") |> result.try(fn(_) { Ok(ctx) })
    False -> {
      let inserted_msg =
        log.format("Success: '{0}' was added to banned phrases", [input_words])
      let deleted_msg =
        log.format("Success: '{0}' was removed from banned phrases", [
          input_words,
        ])

      cmd_utils.insert_or_delete_and_reply(
        ctx,
        ["banned_words"],
        fn(cs) { cs.banned_words },
        input_words,
        inserted_msg,
        deleted_msg,
      )
    }
  }
}

// Checker for messages
pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  log.debug(ctx.dependencies.log, "banned_words")
  let next = fn() { next(ctx, upd) }
  let banned_words = ctx.session.chat_settings.banned_words
  let needs_check = !list.is_empty(banned_words)
  use <- bool.lazy_guard(!needs_check, next)

  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: True,
    next:,
  )

  handle.upd(
    upd,
    fn(message) {
      handle.real_sender(
        message,
        fn(user) {
          let contains_banned =
            helpers.contains_opt(banned_words, message.text)
            || helpers.contains_opt(banned_words, message.caption)
            || helpers.contains(banned_words, helpers.get_fullname(user))

          use <- bool.lazy_guard(!contains_banned, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: banned_words Reason: banned word in message or name.",
            [
              helpers.view_chat(message.chat),
              helpers.view_user(user),
            ],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) { api_calls.get_rid_of_usersender(ctx, user.id) })
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        },
        fn(chatsender) {
          let contains_banned =
            helpers.contains_opt(banned_words, message.text)
            || helpers.contains_opt(banned_words, message.caption)
            || helpers.contains_opt(banned_words, chatsender.title)

          use <- bool.lazy_guard(!contains_banned, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: banned_words Reason: banned word in message or name.",
            [
              helpers.view_chat(message.chat),
              helpers.view_chat(chatsender),
            ],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender(ctx, chatsender)
          })
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        },
        next,
      )
    },
    fn(chat_member_updated) {
      use user <- handle.joined_user(chat_member_updated, next)

      let contains_banned =
        helpers.contains(banned_words, helpers.get_fullname(user))

      use <- bool.lazy_guard(!contains_banned, next)

      log.printf(
        "Ctx: {0} Ban {1} Filter: banned_words Reason: user joined with banned word in name.",
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
      handle.reaction_sender(
        reaction,
        fn(user) {
          let contains_banned =
            helpers.contains(banned_words, helpers.get_fullname(user))

          use <- bool.lazy_guard(!contains_banned, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: banned_words Reason: reaction from user with banned word in name.",
            [
              helpers.view_chat(reaction.chat),
              helpers.view_user(user),
            ],
          )

          api_calls.get_rid_of_usersender_reactions(
            ctx,
            reaction.chat.id,
            user.id,
          )
          |> result.try(fn(_) { api_calls.get_rid_of_usersender(ctx, user.id) })
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        },
        fn(chatsender) {
          let contains_banned =
            helpers.contains_opt(banned_words, chatsender.title)

          use <- bool.lazy_guard(!contains_banned, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: banned_words Reason: reaction from chat with banned word in title.",
            [
              helpers.view_chat(reaction.chat),
              helpers.view_chat(chatsender),
            ],
          )

          api_calls.get_rid_of_chatsender_reactions(
            ctx,
            reaction.chat.id,
            chatsender.id,
          )
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender(ctx, chatsender)
          })
          |> result.map(fn(_) { Nil })
          |> result.lazy_unwrap(next)
        },
        next,
      )
    },
    next,
  )
}
