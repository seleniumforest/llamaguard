import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import infra/reply.{reply}
import infra/storage
import models/error.{type BotError}
import sqlight
import telega/api
import telega/model/types.{Int}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let current_state = ctx.session.chat_settings.check_chat_clones
  let new_state = !current_state

  storage.set_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "check_chat_clones",
    sqlight.bool(new_state),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False ->
        "Success: bot will NOT try to find accounts whose name is similar to chat title"
      True ->
        "Success: bot will try to find accounts whose name is similar to chat title"
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(!ctx.session.chat_settings.check_chat_clones, fn() {
    next(ctx, upd)
  })

  case upd {
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.CommandUpdate(message:, ..)
    | update.EditedBusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.MessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      let is_forwarded_post =
        message.from |> option.map(fn(u) { u.id }) == Some(777_000)

      use <- bool.lazy_guard(is_forwarded_post, fn() { next(ctx, upd) })

      case message.sender_chat {
        Some(sc) -> {
          let sender_chat_title = sc.title |> option.unwrap("")
          let chat_title = message.chat.title |> option.unwrap("")
          log.printf("comparing {0} with {1}", [sender_chat_title, chat_title])
          let compare_result = smart_compare(sender_chat_title, chat_title)

          case compare_result {
            False -> Some(next(ctx, upd))
            True -> {
              log.printf("Delete message from {0} id {1} reason: chat clone", [
                sender_chat_title,
                sc.id |> int.to_string,
              ])

              let _ =
                api.delete_message(
                  ctx.config.api_client,
                  types.DeleteMessageParameters(
                    chat_id: Int(message.chat.id),
                    message_id: message.message_id,
                  ),
                )

              api.ban_chat_sender_chat(
                ctx.config.api_client,
                types.BanChatSenderChatParameters(
                  chat_id: Int(upd.chat_id),
                  sender_chat_id: sc.id,
                ),
              )
              |> result.try(fn(_) { Ok(Some(Nil)) })
              |> result.lazy_unwrap(fn() { Some(next(ctx, upd)) })
            }
          }
        }
        None -> {
          case message.from {
            Some(from) -> {
              let last_first =
                from.last_name |> option.unwrap("") <> " " <> from.first_name
              let first_last =
                from.first_name <> " " <> from.last_name |> option.unwrap("")
              let chat_title = message.chat.title |> option.unwrap("")
              let compare_result =
                smart_compare(last_first, chat_title)
                || smart_compare(first_last, chat_title)

              case compare_result {
                False -> Some(next(ctx, upd))
                _ -> {
                  log.printf("Ban user lf: {0} fl: {1} reason: chat clone", [
                    last_first,
                    first_last,
                  ])

                  api.ban_chat_member(
                    ctx.config.api_client,
                    types.BanChatMemberParameters(
                      chat_id: Int(upd.chat_id),
                      user_id: from.id,
                      until_date: option.None,
                      revoke_messages: option.Some(True),
                    ),
                  )
                  |> result.try(fn(_) { Ok(Some(Nil)) })
                  |> result.lazy_unwrap(fn() { Some(next(ctx, upd)) })
                }
              }
            }
            None -> Some(next(ctx, upd))
          }
        }
      }
      |> option.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}

pub fn smart_compare(str1: String, str2: String) -> Bool {
  case str1 |> string.is_empty || str2 |> string.is_empty {
    False -> normalize(str1) == normalize(str2)
    True -> False
  }
}

fn normalize(str: String) -> String {
  str
  |> string.lowercase()
  |> string.to_graphemes()
  |> list.chunk(by: fn(x) { x })
  |> list.map(fn(group) {
    case list.first(group) {
      Ok(char) -> char
      Error(_) -> ""
    }
  })
  |> list.map(fn(x) {
    dict.get(similarity_map(), x)
    |> result.unwrap(x)
  })
  |> string.join("")
  |> string.trim()
}

//todo give this task to llm
fn similarity_map() -> Dict(String, String) {
  dict.from_list([
    // Group 4
    #("а", "4"),
    #("a", "4"),
    #("ч", "4"),
    // // Group 8
    #("в", "8"),
    #("б", "8"),
    #("b", "8"),
    #("6", "8"),
    // Group 3
    #("е", "3"),
    #("e", "3"),
    #("з", "3"),
    #("э", "3"),
    #("€", "3"),
    // Group 1
    #("i", "1"),
    #("l", "1"),
    #("|", "1"),
    #("!", "1"),
    // Group 0
    #("o", "0"),
    #("о", "0"),
    // Group 5
    #("с", "5"),
    #("c", "5"),
    #("s", "5"),
    #("$", "5"),
    // Group 7
    #("т", "7"),
    #("t", "7"),
    // Group Y
    #("y", "y"),
    #("v", "y"),
    // Group X
    #("ж", "x"),
    #("%", "x"),
    // Group W
    #("ш", "w"),
    #("щ", "w"),
    #("w", "w"),
    // Group R
    #("я", "r"),
    #("r", "r"),
    //cyrillic-latin
    #("к", "k"),
    #("у", "y"),
    #("ё", "e"),
    #("е", "e"),
    #("B", "b"),
    #("х", "x"),
    #("н", "h"),
    #("р", "p"),
    #("т", "t"),
    #("M", "m"),
  ])
}
