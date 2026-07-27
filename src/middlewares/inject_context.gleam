import gleam/int
import gleam/option
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cache_validation
import infra/handle
import infra/log
import infra/storage/chat_settings as cs_storage
import infra/storage/user_chat as uc_storage
import models/bot_session.{BotSession}
import models/error
import telega/bot.{Context}
import telega/update.{type Update}

pub fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: BotContext, update: Update) {
      let chat =
        cs_storage.get_chat(db, ctx.update.chat_id)
        |> result.try_recover(fn(err) {
          case err {
            error.EmptyDataError -> {
              log.printf("Creating chat settings for new key {0}", [
                ctx.update.chat_id |> int.to_string,
              ])

              let title = case api_calls.get_chat(ctx, ctx.update.chat_id) {
                Ok(chat) -> {
                  case chat.title, chat.username {
                    option.Some(title), option.Some(username) ->
                      log.format("{0} ({1})", [title, username])
                    option.Some(title), option.None -> title
                    option.None, option.Some(username) -> username
                    _, _ -> ""
                  }
                }
                Error(e) -> {
                  log.printf_err(
                    "WARN: error returned when tried to get chat info fn inject_chat_settings err {0}"
                      <> "Processing chat id {1} with empty title",
                    [string.inspect(e), int.to_string(ctx.update.chat_id)],
                  )
                  ""
                }
              }

              cs_storage.create_chat_settings(db, ctx.update.chat_id, title)
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
          //not sure what to return when it should never happen
          //if THIS branch reached, maybe ask user to remove bot and add it again???
          //or maybe add command /reset which resets all the settings???  

          //Ok(ctx)
        }
        Ok(chat_settings) -> {
          let session = BotSession(..ctx.session, chat_settings:, db:)
          let first_injected_ctx = Context(..ctx, session:)

          let #(new_ctx, errors) =
            cache_validation.validate_all(first_injected_ctx)
          //echo errors
          case errors {
            [] -> handler(new_ctx, update)
            _ -> {
              log.printf_err(
                "ERROR: Could not revalidate caches for chat {0} errors: {1} "
                  <> "Some data may be stalled. If you see A LOT of these messages, "
                  <> "this is NOT normal behaviour, but rare 1-2 messages are ok.",
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

pub fn inject_user_chat() {
  fn(handler) {
    fn(ctx: BotContext, update: Update) {
      let real_sender = handle.get_real_sender_by_upd(update)

      let user_chat =
        uc_storage.get_user_chat(
          ctx.session.db,
          real_sender.0,
          ctx.update.chat_id,
        )
        |> option.from_result()

      let session = BotSession(..ctx.session, user_chat:, real_sender:)
      handler(Context(..ctx, session:), update)
    }
  }
}
