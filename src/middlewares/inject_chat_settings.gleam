import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/timestamp
import infra/alias.{type BotContext}
import infra/api_calls
import infra/log
import infra/storage.{Array, Value}
import models/bot_session.{BotSession}
import models/chat_settings.{type ChatSettings}
import models/error
import telega/bot
import telega/model/types
import telega/update

pub fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: BotContext, update: update.Update) {
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
            "ERROR: Could not get chat settings for chat {0} err: {1} Processing with default chat settings. This is NOT normal behaviour",
            [ctx.update.chat_id |> string.inspect, e |> string.inspect],
          )

          handler(ctx, update)
        }
        Ok(cs) -> {
          validate_admin_list(ctx, update, cs)
          |> result.try(fn(x) {
            let session = BotSession(..ctx.session, chat_settings: x, db:)
            let modified_ctx = bot.Context(..ctx, session:)
            handler(modified_ctx, update)
          })
        }
      }
    }
  }
}

//todo should it be permanent db or in-memory cache?

const cache_ttl_sec = 600

fn validate_admin_list(
  ctx: BotContext,
  upd: update.Update,
  chat_settings: ChatSettings,
) -> Result(ChatSettings, error.BotError) {
  let is_private_chat = upd.chat_id > 0
  let #(now, _) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  let cache_expired = chat_settings.admins_last_upd + cache_ttl_sec < now

  use <- bool.lazy_guard(is_private_chat || !cache_expired, fn() {
    Ok(chat_settings)
  })

  api_calls.get_chat_administrators(ctx, upd.chat_id)
  |> result.map(fn(ls) {
    let admin_ids =
      list.filter_map(ls, fn(x) {
        case x {
          types.ChatMemberAdministratorChatMember(m) -> Ok(m.user.id)
          types.ChatMemberOwnerChatMember(m) -> Ok(m.user.id)
          _ -> Error(Nil)
        }
      })

    storage.save_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "admins_id_list",
      Array(admin_ids |> list.map(fn(x) { storage.Int(x) })),
    )
    |> result.try(fn(_) {
      storage.save_chat_property(
        ctx.session.db,
        ctx.update.chat_id,
        "admins_last_upd",
        Value(storage.Int(now)),
      )
    })
    |> result.try(fn(_) {
      chat_settings.ChatSettings(
        ..chat_settings,
        admins_id_list: option.Some(admin_ids),
        admins_last_upd: now,
      )
      |> Ok
    })
  })
  |> result.flatten
}
