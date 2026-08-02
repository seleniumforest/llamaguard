import gleam/bool
import gleam/list
import gleam/option
import gleam/regexp
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/args
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import infra/reply.{reply}
import infra/storage/user_chat as uc_repo
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  let usage_msg =
    "Usage: /banLang <unicode_ext> (Han for Chinese, Hangul for Korean, Arabic etc.)"

  use lang <- args.use_first_arg(cmd.text, fn(str) { str }, fn() {
    reply(ctx, usage_msg) |> result.try(fn(_) { Ok(ctx) })
  })

  let is_valid_lang =
    ctx.dependencies.resources.unicode_script_extensions
    |> list.any(fn(x) {
      let sanitized = x |> string.lowercase() |> string.trim
      let lang = lang |> string.lowercase() |> string.trim
      sanitized == lang
    })

  let inserted_msg =
    log.format("Success: language {0} was added to banned languages list", [
      lang,
    ])

  let deleted_msg =
    log.format("Success: language {0} was removed from banned languages list", [
      lang,
    ])

  case is_valid_lang {
    True -> {
      cmd_utils.insert_or_delete_and_reply(
        ctx,
        ["banned_languages"],
        fn(cs) { cs.banned_languages },
        lang,
        inserted_msg,
        deleted_msg,
      )
    }
    False -> {
      reply(ctx, log.format("Language {0} not found. {1}", [lang, usage_msg]))
      |> result.try(fn(_) { Ok(ctx) })
    }
  }
}

pub fn checker(
  ctx: BotContext,
  upd: update.Update,
  next: fn(BotContext, update.Update) -> Nil,
) -> Nil {
  log.debug(ctx.dependencies.log, "ban_language")
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(ctx.session.chat_settings.banned_languages == [], next)

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
    fn(message) { check_msg(ctx, message, next) },
    fn(chat_member_updated) {
      use joined <- handle.joined_user(chat_member_updated, next)
      check_joined_user(ctx, joined, chat_member_updated.chat, next)
    },
    fn(reaction) {
      handle.reaction_sender(
        reaction,
        fn(user) { check_reacted_user(ctx, user, reaction, next) },
        fn(chat) { check_reacted_chat(ctx, chat, reaction, next) },
        next,
      )
    },
    fn() { next() },
  )
}

fn check_reacted_chat(
  ctx: BotContext,
  chatsender: types.Chat,
  reaction: types.MessageReactionUpdated,
  next: fn() -> Nil,
) {
  let text = chatsender.title |> option.unwrap("")
  echo text

  case
    helpers.check_banned_lang(ctx.session.chat_settings.banned_languages, text)
  {
    True -> {
      log.printf(
        "Ctx: {0} Ban {1} Filter: ban_language Reason: reacted with restricted language symbols in the name.",
        [
          helpers.view_chat(reaction.chat),
          helpers.view_chat(chatsender),
        ],
      )

      api_calls.get_rid_of_chatsender(ctx, chatsender)
      |> result.try(fn(_) {
        api_calls.get_rid_of_chatsender_reactions(
          ctx,
          reaction.chat.id,
          chatsender.id,
        )
      })
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(next)
    }
    False -> next()
  }
}

fn check_reacted_user(
  ctx: BotContext,
  user: types.User,
  reaction: types.MessageReactionUpdated,
  next: fn() -> Nil,
) {
  let text = helpers.get_fullname(user)

  case
    helpers.check_banned_lang(ctx.session.chat_settings.banned_languages, text)
  {
    True -> {
      log.printf(
        "Ctx: {0} Ban {1} Filter: ban_language Reason: reacted with restricted language symbols in the name.",
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
    }
    False -> next()
  }
}

fn check_joined_user(
  ctx: BotContext,
  user: types.User,
  chat: types.Chat,
  next: fn() -> Nil,
) {
  let text = helpers.get_fullname(user)

  case
    helpers.check_banned_lang(ctx.session.chat_settings.banned_languages, text)
  {
    True -> {
      log.printf(
        "Ctx: {0} Ban {1} Filter: ban_language Reason: joined with restricted language symbols in the name.",
        [
          helpers.view_chat(chat),
          helpers.view_user(user),
        ],
      )

      let _ = uc_repo.set_user_banned(ctx.dependencies.db, user.id, chat.id)
      let _ = api_calls.get_rid_of_usersender(ctx, user.id)

      Nil
    }
    False -> next()
  }
}

fn check_msg(ctx: BotContext, message: types.Message, next: fn() -> Nil) -> Nil {
  let text = handle.get_visible_text(message)

  let regexp_str =
    "["
    <> ctx.session.chat_settings.banned_languages
    |> list.map(fn(x) { "\\p{Script_Extensions=" <> x <> "}" })
    |> string.join("")
    <> "]"

  case regexp.from_string(regexp_str) {
    Ok(reg) -> {
      let check_result = regexp.check(reg, text)
      use <- bool.lazy_guard(!check_result, next)

      let _ = api_calls.get_rid_of_msg(ctx, message.message_id)

      handle.real_sender(
        message,
        fn(from) {
          log.printf(
            "Ctx: {0} Ban {1} Filter: ban_language Reason: message with restricted language symbols.",
            [
              helpers.view_chat(message.chat),
              helpers.view_user(from),
            ],
          )

          let _ =
            uc_repo.set_user_banned(
              ctx.dependencies.db,
              from.id,
              message.chat.id,
            )
          let _ = api_calls.get_rid_of_usersender(ctx, from.id)

          Nil
        },
        fn(sc) {
          log.printf("Ctx: {0} Ban {1} reason: restricted language symbols.", [
            helpers.view_chat(message.chat),
            helpers.view_chat(sc),
          ])

          let _ = api_calls.get_rid_of_chatsender(ctx, sc)
          Nil
        },
        next,
      )
    }
    Error(err) -> {
      log.printf_err(
        "WARN: Could not build regexp to check message for banned languages. "
          <> "Skipping check for banned languages. "
          <> "regexp_str: {0}, banned_languages: {1}, err:{2}",
        [
          regexp_str,
          ctx.session.chat_settings.banned_languages |> string.inspect,
          err |> string.inspect,
        ],
      )
      next()
    }
  }
}
