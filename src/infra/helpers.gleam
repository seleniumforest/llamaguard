import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string
import gleam/time/timestamp
import infra/alias.{type BotContext}
import infra/api_calls
import infra/log
import models/error
import telega/model/decoder
import telega/model/encoder
import telega/model/types.{type Message}

pub fn is_forwarded_msg(msg: Message) {
  msg.reply_to_message
  |> option.then(fn(rtm) { rtm.is_automatic_forward })
  |> option.unwrap(False)
}

pub fn get_fullname(user: types.User) {
  case user.last_name {
    option.None -> user.first_name
    Some(ln) -> log.format("{0} {1}", [user.first_name, ln])
  }
}

pub fn try_get_fullname(user: Option(types.User)) {
  case user {
    option.None -> ""
    Some(u) -> get_fullname(u)
  }
}

pub fn view_chat(chat: types.Chat) {
  log.format("[{0} (id:{1})]", [
    chat.title |> option.unwrap("<no title>"),
    chat.id |> int.to_string,
  ])
}

pub fn view_user(user: types.User) {
  log.format("[{0} (id:{1})]", [
    get_fullname(user),
    user.id |> int.to_string,
  ])
}

pub fn option_guard(opt: Option(a), default: b, next: fn(a) -> b) -> b {
  case opt {
    Some(value) -> next(value)
    None -> default
  }
}

pub fn now() {
  let #(now, _) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds
  now
}

// all possible options
// @username
// id@username
// id
pub fn match_ids(id1: String, id2: String) {
  use <- bool.guard(id1 == id2, True)
  case string.split_once(id1, "@"), string.split_once(id2, "@") {
    //id and id
    Ok(#(uid1, _)), Ok(#(uid2, _)) if uid1 != "" && uid2 != "" -> uid1 == uid2
    //@username and @username
    Ok(#(_, n1)), Ok(#(_, n2)) if n1 != "" && n2 != "" -> n1 == n2
    //id with id@username
    Error(_), Ok(#(uid, _uname)) if id1 != "" && uid != "" -> id1 == uid
    //id@username with id
    Ok(#(id, _name)), Error(_) if id2 != "" && id != "" -> id2 == id
    _, _ -> False
  }
}

pub fn join_id(id: #(Int, Option(String))) {
  case id.1 {
    option.None -> int.to_string(id.0)
    Some(u) -> {
      let without_at = case u {
        "@" <> uname -> uname
        _ -> u
      }

      log.format("{0}@{1}", [int.to_string(id.0), without_at])
    }
  }
}

pub fn contains(words: List(String), text: String) {
  case string.is_empty(text) {
    True -> False
    False -> {
      let normalized =
        string.lowercase(text)
        |> string.split(" ")
        |> list.map(string.trim)
        |> list.filter(fn(x) { !string.is_empty(x) })
        |> string.join(" ")

      words
      |> list.any(fn(word) { string.contains(normalized, word) })
    }
  }
}

pub fn contains_opt(words: List(String), text: option.Option(String)) {
  case text {
    Some(text) -> contains(words, text)
    None -> False
  }
}

pub fn check_banned_lang(banned_langs: List(String), text: String) {
  use <- bool.guard(string.is_empty(text), False)

  let regexp_str =
    "["
    <> banned_langs
    |> list.map(fn(x) { "\\p{Script_Extensions=" <> x <> "}" })
    |> string.join("")
    <> "]"

  case regexp.from_string(regexp_str) {
    Ok(reg) -> regexp.check(reg, text)
    Error(e) -> {
      log.printf_err(
        "WARN: Could not build regexp to check message for banned languages. "
          <> "Skipping check for banned languages. "
          <> "regexp_str: {0}, banned_languages: {1}, err:{2}",
        [
          regexp_str,
          banned_langs |> string.inspect,
          e |> string.inspect,
        ],
      )

      False
    }
  }
}

const ttl = 60_000

pub fn get_chat_member_cached(ctx: BotContext, chat_id: Int, user_id: Int) {
  let key = int.to_string(chat_id) <> ":" <> int.to_string(user_id)
  use <- bool.lazy_guard(user_id <= 0, fn() {
    let msg =
      log.format("fn get_chat_member_cached negative user_id {0} supplied", [
        int.to_string(user_id),
      ])

    log.print(msg)
    Error(error.GenericError(msg))
  })

  case ctx.dependencies.cache.get(key) {
    Ok(got) ->
      case got {
        Some(json) -> {
          json.parse(json, decoder.chat_member_decoder())
          |> result.map_error(fn(e) { error.InvalidValueError(e) })
        }
        None -> {
          api_calls.get_chat_member(ctx, chat_id, user_id)
          |> result.map_error(fn(e) {
            log.printf_err(
              "WARN: get_chat_member returned error. fn get_chat_member_cached err {0} Some shit may happened.",
              [string.inspect(e)],
            )

            e
          })
          |> result.try(fn(member) {
            let encoded = encoder.encode_chat_member(member) |> json.to_string

            ctx.dependencies.cache.set_with_ttl(key, encoded, ttl)
            |> result.map_error(fn(e) {
              log.printf_err(
                "WARN: set_with_ttl returned error. fn get_chat_member_cached err {0} Some shit may happened.",
                [string.inspect(e)],
              )

              e
            })
            |> result.map(fn(_) { member })
          })
        }
      }
    Error(e) -> {
      log.printf_err(
        "WARN: cache.get returned error. fn get_chat_member_cached err {0} Some shit may happened.",
        [string.inspect(e)],
      )
      api_calls.get_chat_member(ctx, chat_id, user_id)
    }
  }
}
