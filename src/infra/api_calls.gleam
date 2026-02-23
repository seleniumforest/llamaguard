import gleam/option
import gleam/result
import infra/alias.{type BotContext}
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
      revoke_messages: option.Some(False),
    ),
  )
  |> result.map_error(fn(e) { error.TelegaLibError(e) })
}

pub fn get_rid_of_msg(ctx: BotContext, message_id: Int) {
  api.delete_message(
    ctx.config.api_client,
    types.DeleteMessageParameters(
      chat_id: Int(ctx.update.chat_id),
      message_id: message_id,
    ),
  )
  |> result.map_error(fn(e) { error.TelegaLibError(e) })
}

pub fn get_rid_of_chat(ctx: BotContext, sender_chat: types.Chat) {
  api.ban_chat_sender_chat(
    ctx.config.api_client,
    types.BanChatSenderChatParameters(
      chat_id: Int(ctx.update.chat_id),
      sender_chat_id: sender_chat.id,
    ),
  )
  |> result.map_error(fn(e) { error.TelegaLibError(e) })
}

pub fn get_chat_member(ctx: BotContext, chat_id: Int, user_id: Int) {
  api.get_chat_member(
    ctx.config.api_client,
    GetChatMemberParameters(chat_id: Int(chat_id), user_id:),
  )
  |> result.map_error(fn(e) { error.TelegaLibError(e) })
  //todo caching expected in the future
}

pub fn get_chat_administrators(ctx: BotContext, chat_id: Int) {
  api.get_chat_administrators(
    ctx.config.api_client,
    GetChatAdministratorsParameters(Int(chat_id)),
  )
  |> result.map_error(fn(e) { error.TelegaLibError(e) })
}
