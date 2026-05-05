import gleam/int
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/cache_validation
import infra/log
import infra/storage/chat_settings as cs_storage
import models/bot_session.{BotSession}
import models/error
import telega/bot
import telega/update

pub fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: BotContext, update: update.Update) {
      let chat =
        cs_storage.get_chat(db, ctx.update.chat_id)
        |> result.try_recover(fn(err) {
          case err {
            error.EmptyDataError -> {
              log.printf("Creating chat settings for new key {0}", [
                ctx.update.chat_id |> int.to_string,
              ])

              cs_storage.create_chat_settings(db, ctx.update.chat_id)
            }
            _ -> Error(err)
          }
        })

      case chat {
        Error(e) -> {
          log.printf_err(
            "ERROR: Could not get chat settings for chat {0} err: {1} "
              <> "Processing with default chat settings. This is NOT normal behaviour",
            [ctx.update.chat_id |> string.inspect, e |> string.inspect],
          )

          handler(ctx, update)
        }
        Ok(chat_settings) -> {
          let session = BotSession(..ctx.session, chat_settings:, db:)
          let first_injected_ctx = bot.Context(..ctx, session:)

          let #(new_ctx, errors) =
            cache_validation.validate_all(first_injected_ctx)

          case errors {
            [] -> handler(new_ctx, update)
            _ -> {
              log.printf_err(
                "ERROR: Could not revalidate caches for chat {0} errors: {1} "
                  <> "Some data may be stalled. If you see A LOT of these messages, "
                  <> "this is NOT normal behaviour, but 1-3 messages are probably ok.",
                [ctx.update.chat_id |> string.inspect, errors |> string.inspect],
              )
              handler(new_ctx, update)
            }
          }
        }
      }
    }
  }
}
