import gleam/bool
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/args
import infra/helpers
import infra/log
import infra/reply.{reply}
import infra/storage/chat_settings as cs_storage
import infra/storage/user_chat as uc_repo
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  case args.try_parse_str(cmd.text, 1), ctx.update {
    Some(arg), update.CommandUpdate(..) -> {
      let is_valid_lang =
        ctx.session.resources.unicode_script_extensions
        |> list.find(fn(x) {
          let sanitized = x |> string.lowercase() |> string.trim
          sanitized == arg |> string.lowercase() |> string.trim
        })

      case is_valid_lang {
        Ok(lang) -> {
          let is_already_added =
            ctx.session.chat_settings.banned_languages |> list.contains(lang)
          let new_list = case is_already_added {
            True ->
              ctx.session.chat_settings.banned_languages
              |> list.filter(fn(x) { x != lang })
            False -> [lang, ..ctx.session.chat_settings.banned_languages]
          }

          let _ =
            cs_storage.save_chat_property(
              ctx.session.db,
              ctx.update.chat_id,
              ["banned_languages"],
              json.array(new_list, json.string),
            )
            |> result.try(fn(_) {
              reply(
                ctx,
                log.format("Success: language {0} {1} banned languages list", [
                  lang,
                  case is_already_added {
                    True -> "was removed from"
                    False -> "was added to"
                  },
                ]),
              )
            })
        }
        Error(_) ->
          reply(
            ctx,
            log.format("Language {0} not found. Usage: /banLang Han", [arg]),
          )
      }
    }
    _, _ -> reply(ctx, "Usage: /banLang Han")
  }
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn checker(
  ctx: BotContext,
  upd: update.Update,
  next: fn(BotContext, update.Update) -> Nil,
) -> Nil {
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(ctx.session.is_trusted_sender, next)
  use <- bool.lazy_guard(ctx.session.chat_settings.banned_languages == [], next)

  use message <- helpers.has_msg(upd, next)

  //TODO for now, chats always on quarantine. Think how can we handle this
  let is_sender_on_quarantine = case ctx.session.user_chat {
    Some(uc) -> uc.on_quarantine
    None ->
      case ctx.session.real_sender {
        #(id, _) if id < 0 -> True
        _ -> False
      }
  }
  let strict_mode_on = ctx.session.chat_settings.strict_mode_newcomers > 0
  use <- bool.lazy_guard(!is_sender_on_quarantine || !strict_mode_on, next)
  let text = helpers.get_visible_text(message)
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

      helpers.handle_sender(
        message,
        fn(from) {
          log.printf("Ctx: {0} Ban {1} reason: restricted language symbols.", [
            helpers.view_chat(message.chat),
            helpers.view_user(from),
          ])

          let _ =
            uc_repo.delete_user_chat(ctx.session.db, from.id, message.chat.id)
          let _ = api_calls.get_rid_of_user(ctx, from.id)

          Nil
        },
        fn(sc) {
          log.printf("Ctx: {0} Ban {1} reason: restricted language symbols.", [
            helpers.view_chat(message.chat),
            helpers.view_chat(sc),
          ])

          let _ = api_calls.get_rid_of_chat(ctx, sc)
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
