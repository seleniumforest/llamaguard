import gleam/bool
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
  case upd {
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      let no_banned_langs = ctx.session.chat_settings.banned_languages == []
      let strict_mode_on = ctx.session.chat_settings.strict_mode_newcomers > 0
      //TODO for now, chats always on quarantine. Think how can we handle this
      let is_sender_on_quarantine = case message.sender_chat {
        Some(_) -> True
        None ->
          case uc_repo.get_user_chat(ctx.session.db, upd.from_id, upd.chat_id) {
            Ok(uc) -> uc.on_quarantine
            Error(_) -> False
          }
      }

      //let is_forward_to_check = helpers.is_forwarded_msg(message)

      use <- bool.lazy_guard(
        no_banned_langs || !is_sender_on_quarantine || !strict_mode_on,
        //|| !is_forward_to_check,
        fn() { next(ctx, upd) },
      )

      case join_string_opts(message.text, message.caption) {
        Some(text) -> {
          let regexp_str =
            "["
            <> ctx.session.chat_settings.banned_languages
            |> list.map(fn(x) { "\\p{Script_Extensions=" <> x <> "}" })
            |> string.join("")
            <> "]"

          case regexp.from_string(regexp_str) {
            Ok(reg) -> {
              let check_result = regexp.check(reg, text)
              use <- bool.lazy_guard(!check_result, fn() { next(ctx, upd) })

              let _ = api_calls.get_rid_of_msg(ctx, message.message_id)

              case message.sender_chat, message.from {
                Some(sc), _ -> {
                  log.printf(
                    "Ctx: {0} Ban {1} message: {2} reason: restricted language symbols.",
                    [
                      helpers.view_chat(message.chat),
                      helpers.view_chat(sc),
                      text,
                    ],
                  )

                  let _ = api_calls.get_rid_of_chat(ctx, sc)
                  Nil
                }
                _, Some(from) -> {
                  log.printf(
                    "Ctx: {0} Ban {1} message: {2} reason: restricted language symbols.",
                    [
                      helpers.view_chat(message.chat),
                      helpers.view_user(from),
                      text,
                    ],
                  )

                  let _ =
                    uc_repo.delete_user_chat(
                      ctx.session.db,
                      from.id,
                      message.chat.id,
                    )
                    |> result.try(fn(_) {
                      api_calls.get_rid_of_user(ctx, from.id)
                    })
                  Nil
                }
                _, _ -> next(ctx, upd)
              }
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
              next(ctx, upd)
            }
          }
        }
        None -> next(ctx, upd)
      }
    }
    _ -> next(ctx, upd)
  }
}

fn join_string_opts(text1: Option(String), text2: Option(String)) {
  case text1, text2 {
    None, None -> None
    _, _ ->
      Some(text1 |> option.unwrap("") <> " " <> text2 |> option.unwrap(""))
  }
}
