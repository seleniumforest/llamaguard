import gleam/int
import gleam/result
import gleam/string
import infra/alias
import infra/log
import infra/storage
import models/bot_session
import models/error
import telega/bot
import telega/update

pub fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: alias.BotContext, update: update.Update) {
      let chat =
        storage.get_chat(db, ctx.update.chat_id)
        |> result.try_recover(fn(err) {
          case err {
            error.EmptyDataError -> {
              log.printf("Creating chat settings for new key {0}", [
                ctx.update.chat_id |> int.to_string,
              ])

              storage.create_chat(db, ctx.update.chat_id)
            }
            _ -> Error(err)
          }
        })

      case chat {
        Error(e) -> {
          log.printf_err(
            "ERROR: Could not get chat settings for chat {0} err: {1} Processing with default handler. This is NOT normal behaviour",
            [ctx.key, e |> string.inspect],
          )

          handler(ctx, update)
        }
        Ok(chat_settings) -> {
          let session =
            bot_session.BotSession(..ctx.session, chat_settings:, db:)
          let modified_ctx = bot.Context(..ctx, session:)
          handler(modified_ctx, update)
        }
      }
    }
  }
}
