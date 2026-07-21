import gleam/dynamic/decode as dyn_decode
import gleam/json
import models/cached.{type Cached, Cached}
import models/decode.{bool_field, int_field, string_list_field}

pub type ChatSettings {
  ChatSettings(
    kick_new_accounts: Int,
    strict_mode_nonmembers: Bool,
    strict_mode_channels: Bool,
    strict_mode_newcomers: Int,
    no_links: Bool,
    check_chat_clones: Bool,
    check_female_name: Bool,
    check_banned_words: Bool,
    banned_words: List(String),
    banned_languages: List(String),
    trusted_users: List(String),
    admins_list: Cached(List(Int)),
    linked_channel_id: Cached(Int),
    cas_enabled: Bool,
    ban_channels: Bool,
    aggressive: Bool,
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
    admins_list: Cached(0, []),
    linked_channel_id: Cached(0, 0),
    cas_enabled: False,
    strict_mode_newcomers: 0,
    ban_channels: False,
    aggressive: False,
    strict_mode_channels: False,
  )
}

pub fn chat_encoder(chat: ChatSettings) {
  json.object([
    #("kick_new_accounts", json.int(chat.kick_new_accounts)),
    #("strict_mode_newcomers", json.int(chat.strict_mode_newcomers)),
    #("strict_mode_nonmembers", json.bool(chat.strict_mode_nonmembers)),
    #("check_chat_clones", json.bool(chat.check_chat_clones)),
    #("check_female_name", json.bool(chat.check_female_name)),
    #("no_links", json.bool(chat.no_links)),
    #("aggressive", json.bool(chat.aggressive)),
    #("cas_enabled", json.bool(chat.cas_enabled)),
    #("ban_channels", json.bool(chat.ban_channels)),
    #("check_banned_words", json.bool(chat.check_banned_words)),
    #("banned_words", json.array(chat.banned_words, json.string)),
    #("trusted_users", json.array(chat.trusted_users, json.string)),
    #("banned_languages", json.array(chat.banned_languages, json.string)),
    #(
      "admins_list",
      cached.cacheify(chat.admins_list, fn(obj) { json.array(obj, json.int) }),
    ),
    #(
      "linked_channel_id",
      cached.cacheify(chat.linked_channel_id, fn(obj) { json.int(obj) }),
    ),
  ])
}

pub fn chat_decoder() {
  use kick_new_accounts <- int_field("kick_new_accounts")
  use strict_mode_nonmembers <- bool_field("strict_mode_nonmembers")
  use strict_mode_channels <- bool_field("strict_mode_channels")
  use strict_mode_newcomers <- int_field("strict_mode_newcomers")
  use check_chat_clones <- bool_field("check_chat_clones")
  use check_female_name <- bool_field("check_female_name")
  use cas_enabled <- bool_field("cas_enabled")
  use no_links <- bool_field("no_links")
  use check_banned_words <- bool_field("check_banned_words")
  use banned_words <- string_list_field("banned_words")
  use banned_languages <- string_list_field("banned_languages")
  use trusted_users <- string_list_field("trusted_users")
  use ban_channels <- bool_field("ban_channels")
  use aggressive <- bool_field("aggressive")
  use admins_list <- cached.decacheify(
    "admins_list",
    dyn_decode.list(dyn_decode.int),
  )
  use linked_channel_id <- cached.decacheify(
    "linked_channel_id",
    dyn_decode.int,
  )

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
    cas_enabled:,
    ban_channels:,
    banned_languages:,
    admins_list:,
    linked_channel_id:,
    aggressive:,
    strict_mode_channels:,
  ))
}
