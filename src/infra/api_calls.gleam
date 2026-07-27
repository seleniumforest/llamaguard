import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/option.{Some}
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

pub fn get_rid_of_usersender(ctx: BotContext, user_id: Int) {
  api.ban_chat_member(
    ctx.config.api_client,
    parameters: BanChatMemberParameters(
      chat_id: Int(ctx.update.chat_id),
      user_id:,
      until_date: option.None,
      revoke_messages: Some(True),
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_msg(ctx: BotContext, message_id: Int) {
  api.delete_message(
    ctx.config.api_client,
    types.DeleteMessageParameters(
      chat_id: Int(ctx.update.chat_id),
      message_id: message_id,
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_chatsender(ctx: BotContext, sender_chat: types.Chat) {
  api.ban_chat_sender_chat(
    ctx.config.api_client,
    types.BanChatSenderChatParameters(
      chat_id: Int(ctx.update.chat_id),
      sender_chat_id: sender_chat.id,
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_usersender_reactions(
  ctx: BotContext,
  chat_id: Int,
  user_id: Int,
) {
  api.delete_all_message_reactions(
    ctx.config.api_client,
    types.DeleteAllMessageReactionsParameters(
      chat_id: Int(chat_id),
      user_id: Some(user_id),
      actor_chat_id: option.None,
    ),
  )
  |> result.map_error(log_err)
}

pub fn get_rid_of_chatsender_reactions(
  ctx: BotContext,
  chat_id: Int,
  actor_chat_id: Int,
) {
  api.delete_all_message_reactions(
    ctx.config.api_client,
    types.DeleteAllMessageReactionsParameters(
      chat_id: Int(chat_id),
      user_id: option.None,
      actor_chat_id: Some(actor_chat_id),
    ),
  )
  |> result.map_error(log_err)
}

/// Identifier of the target message
/// Identifier of the user who set the reaction
/// The reaction to remove from the message
pub fn unban_chat_member(ctx: BotContext, chat_id: Int, user_id: Int) {
  api.unban_chat_member(
    ctx.config.api_client,
    types.UnbanChatMemberParameters(
      chat_id: Int(chat_id),
      user_id:,
      only_if_banned: Some(True),
    ),
  )
  |> result.map_error(log_err)
}

pub fn unban_chat_sender_chat(
  ctx: BotContext,
  chat_id: Int,
  sender_chat_id: Int,
) {
  api.unban_chat_sender_chat(
    ctx.config.api_client,
    types.UnbanChatSenderChatParameters(chat_id: Int(chat_id), sender_chat_id:),
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
    GetChatAdministratorsParameters(Int(chat_id), Some(True)),
  )
  |> result.map_error(log_err)
}

pub fn check_cas(user_id: Int) -> Result(Int, error.BotError) {
  case
    request.to(
      "https://api.cas.chat/check?user_id=" <> user_id |> int.to_string,
    )
  {
    Ok(base_req) -> {
      httpc.send(base_req)
      |> result.map_error(fn(e) {
        log.printf_err("fn: check_cas, err: {0}", [string.inspect(e)])
        error.CasCheckError(e)
      })
      |> result.try(fn(x) { x.body |> decode_offences })
    }
    Error(_) ->
      Error(
        error.GenericError(
          log.format("WARN: request.to returned Nil for user_id = {0}", [
            string.inspect(user_id),
          ]),
        ),
      )
  }
}

fn decode_offences(str: String) {
  let ok_decoder = {
    use ok <- decode.field("ok", decode.bool)
    case ok {
      True -> {
        use offences <- decode.subfield(["result", "offenses"], decode.int)
        decode.success(offences)
      }
      False -> decode.success(0)
    }
  }

  json.parse(str, ok_decoder)
  |> result.map_error(fn(e) {
    log.printf_err("fn: decode_offences, err: {0}", [string.inspect(e)])
    error.InvalidValueError(e)
  })
}

fn log_err(e) {
  log.printf_err("fn: log_err, err: {0}", [string.inspect(e)])
  error.TelegaLibError(e)
}
