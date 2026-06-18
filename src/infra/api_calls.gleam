import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import models/error
import telega/api
import telega/model/types.{
  BanChatMemberParameters, GetChatAdministratorsParameters,
  GetChatMemberParameters, Int,
}

pub fn get_rid_of_user(ctx: BotContext, user_id: Int) {
  api.ban_chat_member(
    ctx.config.api_client,
    parameters: BanChatMemberParameters(
      chat_id: Int(ctx.update.chat_id),
      user_id:,
      until_date: option.None,
      revoke_messages: option.Some(True),
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_msg(ctx: BotContext, message_id: Int) {
  echo "Delete msg:" <> message_id |> int.to_string
  api.delete_message(
    ctx.config.api_client,
    types.DeleteMessageParameters(
      chat_id: Int(ctx.update.chat_id),
      message_id: message_id,
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_chat(ctx: BotContext, sender_chat: types.Chat) {
  api.ban_chat_sender_chat(
    ctx.config.api_client,
    types.BanChatSenderChatParameters(
      chat_id: Int(ctx.update.chat_id),
      sender_chat_id: sender_chat.id,
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_chat_member(ctx: BotContext, chat_id: Int, user_id: Int) {
  api.get_chat_member(
    ctx.config.api_client,
    GetChatMemberParameters(chat_id: Int(chat_id), user_id:),
  )
  |> result.map_error(log_err)
}

pub fn get_chat(ctx: BotContext, chat_id: Int) {
  api.get_chat(ctx.config.api_client, chat_id |> int.to_string)
  |> result.map_error(log_err)
}

pub fn get_chat_administrators(ctx: BotContext, chat_id: Int) {
  api.get_chat_administrators(
    ctx.config.api_client,
    GetChatAdministratorsParameters(Int(chat_id), option.Some(True)),
  )
  |> result.map_error(log_err)
}

pub fn check_cas(user_id: Int) -> Bool {
  let assert Ok(base_req) =
    request.to(
      "https://api.cas.chat/check?user_id=" <> user_id |> int.to_string,
    )

  httpc.send(base_req)
  |> result.map_error(fn(e) {
    log.print_err(e |> string.inspect)
    error.CasCheckError(e)
  })
  |> result.try(fn(x) { x.body |> decode |> Ok() })
  |> result.unwrap(False)
}

fn decode(str: String) -> Bool {
  let ok_decoder = {
    use ok <- decode.field("ok", decode.bool)
    decode.success(ok)
  }

  case json.parse(str, ok_decoder) {
    Ok(val) -> val
    Error(_) -> False
  }
}

fn log_err(e) {
  log.print_err(e |> string.inspect)
  error.TelegaLibError(e)
}
