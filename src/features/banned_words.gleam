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

  use message <- handle.msg(upd, next)

  let contains_banned =
    helpers.contains_opt(banned_words, message.text)
    || helpers.contains_opt(banned_words, message.caption)
    || helpers.contains(banned_words, helpers.try_get_fullname(message.from))
    || helpers.contains_opt(
      banned_words,
      message.sender_chat
        |> option.then(fn(x) { x.title }),
    )

  use <- bool.lazy_guard(!contains_banned, next)

  log.printf("Ctx: {0} Ban {1} reason: banned word in message or name.", [
    helpers.view_chat(message.chat),
    handle.view_sender(message),
  ])

  api_calls.get_rid_of_msg(ctx, message.message_id)
  |> result.try(fn(_) {
    handle.real_sender(
      message,
      fn(user) { api_calls.get_rid_of_usersender(ctx, user.id) },
      fn(chat) { api_calls.get_rid_of_chatsender(ctx, chat) },
      fn() { panic as "unreachable" },
    )
  })
  |> result.map(fn(_) { Nil })
  |> result.lazy_unwrap(next)
}
