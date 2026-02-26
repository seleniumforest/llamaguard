import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  helpers.flip_bool_setting_and_reply(
    ctx,
    "check_chat_clones",
    fn(cs) { cs.check_chat_clones },
    "Success: bot will try to find accounts whose name is similar to chat title",
    "Success: bot will NOT try to find accounts whose name is similar to chat title",
  )
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
    | update.EditedMessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      use <- bool.lazy_guard(message.is_automatic_forward == Some(True), fn() {
        next(ctx, upd)
      })

      case message.sender_chat, message.from {
        Some(sc), _ -> {
          let sender_chat_title = sc.title |> option.unwrap("")
          let chat_title = message.chat.title |> option.unwrap("")
          log.printf("comparing {0} with {1}", [sender_chat_title, chat_title])
          let compare_result = smart_compare(sender_chat_title, chat_title)

          case compare_result {
            False -> next(ctx, upd)
            True -> {
              log.printf("Ban chat {0} id {1} reason: chat clone", [
                sender_chat_title,
                sc.id |> int.to_string,
              ])

              api_calls.get_rid_of_msg(ctx, message.message_id)
              |> result.try(fn(_) { api_calls.get_rid_of_chat(ctx, sc) })
              |> result.try(fn(_) { Ok(Nil) })
              |> result.lazy_unwrap(fn() { next(ctx, upd) })
            }
          }
        }
        None, Some(from) -> {
          let is_clone = is_user_clone(from, message.chat)
          use <- bool.lazy_guard(!is_clone, fn() { next(ctx, upd) })
          log.printf("Ban user: {0} id {1} reason: chat clone", [
            helpers.get_fullname(from),
            from.id |> int.to_string,
          ])

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) { api_calls.get_rid_of_user(ctx, from.id) })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(fn() { next(ctx, upd) })
        }
        _, _ -> next(ctx, upd)
      }
    }
    update.ChatMemberUpdate(chat_member_updated:, ..) -> {
      let is_clone =
        is_user_clone(chat_member_updated.from, chat_member_updated.chat)
      use <- bool.lazy_guard(!is_clone, fn() { next(ctx, upd) })

      log.printf("Ban user: {0} id {1} reason: chat clone", [
        helpers.get_fullname(chat_member_updated.from),
        chat_member_updated.from.id |> int.to_string,
      ])

      api_calls.get_rid_of_user(ctx, chat_member_updated.from.id)
      |> result.try(fn(_) { Ok(Nil) })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}

fn is_user_clone(from: types.User, chat: types.Chat) {
  let last_first = from.last_name |> option.unwrap("") <> " " <> from.first_name
  let first_last = from.first_name <> " " <> from.last_name |> option.unwrap("")
  let chat_title = chat.title |> option.unwrap("")
  smart_compare(last_first, chat_title) || smart_compare(first_last, chat_title)
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
