import gleam/list
import gleam/option.{None, Some}
import infra/handle
import telega/update.{type Update}

pub fn should_check(
  upd: Update,
  //next: fn(BotContext, Update) -> Nil,
) -> Bool {
  //let next = fn() { next(ctx, upd) }
  use message <- handle.msg(upd, fn() { True })

  let is_user_join_or_leave_system_msg = case
    message.left_chat_member,
    message.new_chat_members
  {
    Some(_), None -> True
    None, Some(users) -> users |> list.length > 0
    _, _ -> False
  }

  //https://core.telegram.org/bots/api#message
  //idk should i check all service msgs for now
  case is_user_join_or_leave_system_msg {
    True -> False
    False -> True
  }
}
