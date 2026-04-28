import gleam/dynamic/decode as dyn_decode
import gleam/json
import gleam/option
import models/decode.{
  bool_as_int_encoder, bool_field, int_field, int_list_field, string_list_field,
}

pub type ChatSettings {
  ChatSettings(
    kick_new_accounts: Int,
    strict_mode_nonmembers: Bool,
    strict_mode_newcomers: Int,
    no_links: Bool,
    check_chat_clones: Bool,
    check_female_name: Bool,
    check_banned_words: Bool,
    banned_words: List(String),
    banned_languages: List(String),
    trusted_users: List(String),
    admins_id_list: option.Option(List(Int)),
    admins_last_upd: Int,
    cas_enabled: Bool,
    ban_channels: Bool,
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
    banned_languages: [],
    admins_id_list: option.None,
    admins_last_upd: 0,
    cas_enabled: False,
    strict_mode_newcomers: 0,
    ban_channels: False,
  )
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #("strict_mode_newcomers", json.int(chat.strict_mode_newcomers)),
    #(
      "strict_mode_nonmembers",
      bool_as_int_encoder(chat.strict_mode_nonmembers),
    ),
    #("check_chat_clones", bool_as_int_encoder(chat.check_chat_clones)),
    #("check_female_name", bool_as_int_encoder(chat.check_chat_clones)),
    #("no_links", bool_as_int_encoder(chat.no_links)),
    #("cas_enabled", bool_as_int_encoder(chat.cas_enabled)),
    #("ban_channels", bool_as_int_encoder(chat.ban_channels)),
    #("check_banned_words", bool_as_int_encoder(chat.check_banned_words)),
    #("banned_words", json.array(chat.banned_words, json.string)),
    #("trusted_users", json.array(chat.trusted_users, json.string)),
    #("banned_languages", json.array(chat.banned_languages, json.string)),
  ])
}

pub fn chat_decoder() {
  use kick_new_accounts <- int_field("kick_new_accounts")
  use strict_mode_nonmembers <- bool_field("strict_mode_nonmembers")
  use strict_mode_newcomers <- int_field("strict_mode_newcomers")
  use check_chat_clones <- bool_field("check_chat_clones")
  use check_female_name <- bool_field("check_female_name")
  use cas_enabled <- bool_field("cas_enabled")
  use no_links <- bool_field("no_links")
  use check_banned_words <- bool_field("check_banned_words")
  use banned_words <- string_list_field("banned_words")
  use banned_languages <- string_list_field("banned_languages")
  use trusted_users <- string_list_field("trusted_users")
  use admins_id_list <- int_list_field("admins_id_list")
  use admins_last_upd <- int_field("admins_last_upd")
  use ban_channels <- bool_field("ban_channels")

  dyn_decode.success(ChatSettings(
    kick_new_accounts:,
    no_links:,
    strict_mode_nonmembers:,
    strict_mode_newcomers:,
    check_chat_clones:,
    check_female_name:,
    check_banned_words:,
    banned_words:,
    trusted_users:,
    admins_id_list: option.Some(admins_id_list),
    admins_last_upd:,
    cas_enabled:,
    ban_channels:,
    banned_languages:,
  ))
}
