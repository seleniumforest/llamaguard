import gleam/bool
import gleam/option
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import infra/reply.{reply}
import infra/storage.{Bool, Value}
import models/chat_settings
import models/error.{type BotError}
import telega/model/types

pub fn flip_bool_setting_and_reply(
  ctx: BotContext,
  setting_name: String,
  setting_selector: fn(chat_settings.ChatSettings) -> Bool,
  on_msg: String,
  off_msg: String,
) -> Result(BotContext, BotError) {
  let current_state = setting_selector(ctx.session.chat_settings)
  let new_state = !current_state

  storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    setting_name,
    Value(Bool(new_state)),
  )
  |> result.try(fn(_) {
    reply(ctx, case new_state {
      False -> off_msg
      True -> on_msg
    })
  })
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn get_fullname(user: types.User) {
  case user.last_name {
    option.None -> user.first_name
    option.Some(ln) -> log.format("{0} {1}", [user.first_name, ln])
  }
}

pub fn try_get_fullname(user: option.Option(types.User)) {
  case user {
    option.None -> ""
    option.Some(u) -> get_fullname(u)
  }
}

// all possible options
// @username 
// id@username
// id
pub fn match_ids(id1: String, id2: String) {
  log.printf("matching {0} with {1}", [id1, id2])
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
