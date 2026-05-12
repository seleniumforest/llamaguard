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
import infra/ffi/unicode
import infra/log
import infra/reply.{reply}
import infra/storage/chat_settings as cs_storage
import models/chat_settings
import models/error.{type BotError}
import telega/model/types.{type Message, type MessageEntity}

pub fn flip_bool_setting_and_reply(
  ctx: BotContext,
  setting_name: List(String),
  setting_selector: fn(chat_settings.ChatSettings) -> Bool,
  on_msg: String,
  off_msg: String,
) -> Result(BotContext, BotError) {
  let current_state = setting_selector(ctx.session.chat_settings)
  let new_state = !current_state

  cs_storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    setting_name,
    json.bool(new_state),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False -> off_msg
      True -> on_msg
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn is_forwarded_msg(msg: Message) {
  msg.reply_to_message
  |> option.then(fn(rtm) { rtm.is_automatic_forward })
  |> option.unwrap(False)
}

pub fn get_fullname(user: types.User) {
  case user.last_name {
    option.None -> user.first_name
    option.Some(ln) -> log.format("{0} {1}", [user.first_name, ln])
  }
}

pub fn try_get_fullname(user: Option(types.User)) {
  case user {
    option.None -> ""
    option.Some(u) -> get_fullname(u)
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

pub fn view_sender(msg: Message) {
  handle_sender(msg, view_user, view_chat, fn() { "<no sender>" })
}

pub fn handle_sender(
  msg: Message,
  on_user: fn(types.User) -> a,
  on_channel: fn(types.Chat) -> a,
  fallback: fn() -> a,
) {
  case msg.sender_chat, msg.from {
    Some(sc), None -> on_channel(sc)
    None, Some(from) -> on_user(from)
    _, _ -> fallback()
  }
}

pub fn now() {
  let #(now, _) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds
  now
}

pub fn has_woman_name(female_names: List(String), full_name: String) {
  use <- bool.guard(string.is_empty(full_name), False)

  let assert Ok(reg) = regexp.from_string("[\\p{P}\\p{S}\\p{Emoji}]")

  full_name
  |> unicode.normalize_nfkd
  |> string.lowercase
  |> regexp.replace(reg, _, "")
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.any(fn(x) { !string.is_empty(x) && list.contains(female_names, x) })
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

const allowed_entities = ["phone_number", "date_time"]

fn filter_entities(entities: Option(List(MessageEntity))) {
  entities
  |> option.unwrap([])
  |> list.filter(fn(x) { !list.contains(allowed_entities, x.type_) })
}

pub fn has_restricted_content(msg: Message) -> Bool {
  let is_audio = msg.audio |> option.is_some
  let is_photo = msg.photo |> option.is_some
  let is_video = msg.video |> option.is_some
  let is_video_note = msg.video_note |> option.is_some
  let is_game = msg.game |> option.is_some
  let is_document = msg.document |> option.is_some
  let is_sticker = msg.sticker |> option.is_some
  let is_quote = msg.quote |> option.is_some
  let is_story = msg.story |> option.is_some

  let is_caption_entities =
    filter_entities(msg.caption_entities) |> list.is_empty |> bool.negate

  let has_entities =
    filter_entities(msg.entities) |> list.is_empty |> bool.negate

  let contains_link = case regexp.from_string("https?://\\S+"), msg.text {
    Ok(url_regex), Some(text) -> {
      regexp.scan(with: url_regex, content: text)
      |> list.is_empty
      |> bool.negate
    }
    _, _ -> False
  }

  let contains_emoji = case msg.text {
    Some(text) ->
      case regexp.from_string("\\p{Extended_Pictographic}") {
        Ok(re) -> regexp.check(re, text)
        Error(_) -> False
      }
    None -> False
  }

  is_audio
  || is_photo
  || contains_link
  || has_entities
  || is_video
  || is_video_note
  || is_game
  || is_document
  || is_sticker
  || is_caption_entities
  || contains_emoji
  || is_quote
  || is_story
}

const trusted_ids = [
  777_000,
  //136_817_688,
  42_777,
  1_087_968_824,
  1_271_266_957,
  701_000,
  5_304_255_346,
]

pub fn is_trusted_id(
  trusted_users: List(String),
  user_id: Int,
  username: option.Option(String),
  linked_channel_id: Int,
) -> Bool {
  use <- bool.guard(list.contains(trusted_ids, user_id), True)
  use <- bool.guard(linked_channel_id == user_id, True)

  trusted_users
  |> list.any(fn(x) {
    let match_by_id = match_ids(x, user_id |> int.to_string)
    let match_by_username = case username {
      option.None -> False
      option.Some(u) -> match_ids(x, "@" <> u)
    }

    match_by_id || match_by_username
  })
}

pub fn is_trusted_sender(
  trusted_users: List(String),
  linked_channel_id: Int,
  message: Message,
) {
  echo message.sender_chat
  echo message.from
  let result = case message.sender_chat, message.from {
    //when post from linked channel is forwarded to linked chat, sender_chat is a channel and from is id:777000
    //when user writes on behalf of a channel in a chat, sender_chat is a channel and from is id:136817688 (Channel_Bot)
    Some(sc), Some(from) if from.id == 777_000 || from.id == 136_817_688 -> {
      is_trusted_id(trusted_users, sc.id, sc.username, linked_channel_id)
    }
    None, Some(from) ->
      is_trusted_id(trusted_users, from.id, from.username, linked_channel_id)
    Some(sc), None ->
      is_trusted_id(trusted_users, sc.id, sc.username, linked_channel_id)
    _, _ -> {
      log.print_err(
        "WARN: this code should be unreachable (fn: is_trusted_sender). Some shit may happened",
      )
      False
    }
  }
  echo result
  result
}
