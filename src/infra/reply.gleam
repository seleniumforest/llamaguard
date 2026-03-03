import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/log
import models/error
import telega/api
import telega/model/types.{
  type SendMessageReplyMarkupParameters, AnswerCallbackQueryParameters,
  ReplyParameters, SendMessageParameters,
}
import telega/reply as telega_reply

pub fn replyf(
  ctx: BotContext,
  format: String,
  data: List(String),
) -> Result(types.Message, error.BotError) {
  log.format(format, data) |> reply(ctx, _)
}

pub fn reply(
  ctx: BotContext,
  text: String,
) -> Result(types.Message, error.BotError) {
  case ctx.session.message_id {
    None -> {
      Error(error.GenericError("Trying to reply for update without message ID."))
    }
    Some(message_id) -> {
      api.send_message(
        ctx.config.api_client,
        parameters: SendMessageParameters(
          text:,
          chat_id: types.Int(ctx.update.chat_id),
          business_connection_id: None,
          message_thread_id: None,
          parse_mode: None,
          entities: None,
          link_preview_options: None,
          disable_notification: None,
          protect_content: None,
          message_effect_id: None,
          allow_paid_broadcast: None,
          reply_parameters: Some(ReplyParameters(
            message_id:,
            chat_id: Some(types.Int(ctx.update.chat_id)),
            checklist_task_id: None,
            allow_sending_without_reply: None,
            quote: None,
            quote_parse_mode: None,
            quote_entities: None,
            quote_position: None,
          )),
          reply_markup: None,
        ),
      )
      |> result.map_error(fn(err) { error.TelegaLibError(err) })
    }
  }
}

pub fn reply_markup(
  ctx: BotContext,
  text: String,
  markup: SendMessageReplyMarkupParameters,
) -> Result(types.Message, error.BotError) {
  case ctx.session.message_id {
    None -> {
      Error(error.GenericError("Trying to reply for update without message ID."))
    }
    Some(message_id) -> {
      api.send_message(
        ctx.config.api_client,
        parameters: SendMessageParameters(
          text:,
          chat_id: types.Int(ctx.update.chat_id),
          business_connection_id: None,
          message_thread_id: None,
          parse_mode: None,
          entities: None,
          link_preview_options: None,
          disable_notification: None,
          protect_content: None,
          message_effect_id: None,
          allow_paid_broadcast: None,
          reply_parameters: Some(ReplyParameters(
            message_id:,
            chat_id: Some(types.Int(ctx.update.chat_id)),
            checklist_task_id: None,
            allow_sending_without_reply: None,
            quote: None,
            quote_parse_mode: None,
            quote_entities: None,
            quote_position: None,
          )),
          reply_markup: Some(markup),
        ),
      )
      |> result.map_error(fn(err) { error.TelegaLibError(err) })
    }
  }
}

pub fn answer_callback(ctx, callback_query_id) {
  telega_reply.answer_callback_query(
    ctx,
    AnswerCallbackQueryParameters(
      callback_query_id,
      text: None,
      show_alert: None,
      url: None,
      cache_time: None,
    ),
  )
  |> result.map_error(fn(err) { error.TelegaLibError(err) })
}
