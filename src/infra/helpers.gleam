import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp
import infra/log
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

pub fn is_service_msg(message: Message) {
  let is_user_join_or_leave_system_msg = case
    message.left_chat_member,
    message.new_chat_members
  {
    Some(_), None -> True
    None, Some(users) -> users |> list.length > 0
    _, _ -> False
  }

  is_user_join_or_leave_system_msg
  //https://core.telegram.org/bots/api#message
  //idk should i check all service msgs, maybe in future

  // || message.new_chat_title |> option.is_some
  // || message.new_chat_photo |> option.is_some
  // || message.delete_chat_photo |> option.is_some
  // || message.group_chat_created |> option.is_some
  // || message.supergroup_chat_created |> option.is_some
  // || message.channel_chat_created |> option.is_some
  // || message.message_auto_delete_timer_changed |> option.is_some
  // || message.migrate_to_chat_id |> option.is_some
  // || message.migrate_from_chat_id |> option.is_some
  // || message.pinned_message |> option.is_some
  // || message.video_chat_started |> option.is_some
  // || message.video_chat_ended |> option.is_some
  // || message.video_chat_participants_invited |> option.is_some
  // || message.video_chat_scheduled |> option.is_some
  // || message.proximity_alert_triggered |> option.is_some
  // || message.successful_payment |> option.is_some
  // || message.refunded_payment |> option.is_some
  // || message.users_shared |> option.is_some
  // || message.chat_shared |> option.is_some
  // || message.gift |> option.is_some
  // || message.unique_gift |> option.is_some
  // || message.gift_upgrade_sent |> option.is_some
  // || message.write_access_allowed |> option.is_some
  // || message.boost_added |> option.is_some
  // || message.boost_added |> option.is_some
}
