import gleam/dynamic/decode
import gleam/json
import gleam/option
import models/error

pub type ChatSettings {
  ChatSettings(
    kick_new_accounts: Int,
    strict_mode_nonmembers: Bool,
    no_links: Bool,
    check_chat_clones: Bool,
    check_female_name: Bool,
    check_banned_words: Bool,
    banned_words: List(String),
    trusted_users: List(String),
    admins_id_list: option.Option(List(Int)),
    admins_last_upd: Int,
  )
}

pub fn default() {
  ChatSettings(
    kick_new_accounts: 0,
    no_links: False,
    strict_mode_nonmembers: False,
    check_chat_clones: False,
    check_female_name: False,
    check_banned_words: False,
    banned_words: [],
    trusted_users: [],
    admins_id_list: option.None,
    admins_last_upd: 0,
  )
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #(
      "strict_mode_nonmembers",
      bool_as_int_encoder(chat.strict_mode_nonmembers),
    ),
    #("check_chat_clones", bool_as_int_encoder(chat.check_chat_clones)),
    #("check_female_name", bool_as_int_encoder(chat.check_chat_clones)),
    #("no_links", bool_as_int_encoder(chat.no_links)),
    #("check_banned_words", bool_as_int_encoder(chat.check_banned_words)),
    #("banned_words", json.array(chat.banned_words, json.string)),
    #("trusted_users", json.array(chat.trusted_users, json.string)),
  ])
}

fn bool_as_int_encoder(val: Bool) {
  json.int(case val {
    False -> 0
    True -> 1
  })
}

fn int_to_bool(int: Int) {
  case int {
    0 -> Ok(False)
    1 -> Ok(True)
    _ -> Error(error.GenericError("Cannot decode int as bool"))
  }
}

pub fn chat_decoder() {
  use kick_new_accounts <- int_field("kick_new_accounts")
  use strict_mode_nonmembers <- bool_field("strict_mode_nonmembers")
  use check_chat_clones <- bool_field("check_chat_clones")
  use check_female_name <- bool_field("check_female_name")
  use no_links <- bool_field("no_links")
  use check_banned_words <- bool_field("check_banned_words")
  use banned_words <- string_list_field("banned_words")
  use trusted_users <- string_list_field("trusted_users")
  use admins_id_list <- int_list_field("admins_id_list")
  use admins_last_upd <- int_field("admins_last_upd")

  decode.success(ChatSettings(
    kick_new_accounts:,
    no_links:,
    strict_mode_nonmembers:,
    check_chat_clones:,
    check_female_name:,
    check_banned_words:,
    banned_words:,
    trusted_users:,
    admins_id_list: option.Some(admins_id_list),
    admins_last_upd:,
  ))
}

fn int_field(
  name: String,
  next: fn(Int) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, 0, decode.int)
  next(val)
}

fn bool_field(
  name: String,
  next: fn(Bool) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, 0, decode.int)
  let assert Ok(bool_val) = int_to_bool(val)
  next(bool_val)
}

fn string_list_field(
  name: String,
  next: fn(List(String)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, [], decode.list(decode.string))
  next(val)
}

fn int_list_field(
  name: String,
  next: fn(List(Int)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  use val <- decode.optional_field(name, [], decode.list(decode.int))
  next(val)
}
