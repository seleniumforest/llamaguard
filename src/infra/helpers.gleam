import gleam/option
import gleam/result
import infra/alias.{type BotContext}
import infra/log
import infra/reply.{reply}
import infra/storage
import models/chat_settings
import models/error.{type BotError}
import sqlight
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

  storage.set_chat_property_list(
    ctx.session.db,
    ctx.update.chat_id,
    setting_name,
    sqlight.bool(new_state),
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
