import gleam/bool
import gleam/json
import gleam/list
import gleam/option
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/storage/chat_settings as cs_storage
import models/bot_session.{BotSession}
import models/cached
import models/chat_settings.{type ChatSettings, ChatSettings}
import models/error
import telega/bot
import telega/model/types

const admins_cache_ttl_sec = 60

const linked_channel_cache_ttl_sec = 3600

pub fn validate_all(ctx: BotContext) -> #(BotContext, List(error.BotError)) {
  use new_ctx, errors <- validate_admin_list(ctx, [])
  use new_ctx, errors <- validate_linked_channel(new_ctx, errors)
  #(new_ctx, errors)
}

pub fn validate_one(
  ctx: BotContext,
  handler,
) -> #(BotContext, List(error.BotError)) {
  use new_ctx, errors <- handler(ctx, [])
  #(new_ctx, errors)
}

pub fn validate_admin_list(
  ctx: BotContext,
  errors: List(error.BotError),
  next: fn(BotContext, List(error.BotError)) ->
    #(BotContext, List(error.BotError)),
) -> #(BotContext, List(error.BotError)) {
  let is_private_chat = ctx.update.chat_id > 0
  let now = helpers.now()
  let cache_expired =
    ctx.session.chat_settings.admins_list.updated_at + admins_cache_ttl_sec
    < now

  use <- bool.lazy_guard(is_private_chat || !cache_expired, fn() {
    next(ctx, errors)
  })

  case api_calls.get_chat_administrators(ctx, ctx.update.chat_id) {
    Ok(ls) -> {
      let admin_ids =
        list.filter_map(ls, fn(x) {
          case x {
            types.ChatMemberAdministratorChatMember(m) -> Ok(m.user.id)
            types.ChatMemberOwnerChatMember(m) -> Ok(m.user.id)
            _ -> Error(Nil)
          }
        })

      let admins_list = cached.Cached(updated_at: now, value: admin_ids)

      case
        cs_storage.save_chat_property(
          ctx.session.db,
          ctx.update.chat_id,
          ["admins_list"],
          cached.cacheify(admins_list, fn(data) { json.array(data, json.int) }),
        )
      {
        Ok(_) -> {
          let chat_settings =
            ChatSettings(..ctx.session.chat_settings, admins_list:)

          next(modify_ctx(ctx, chat_settings), errors)
        }
        Error(e) -> next(ctx, [e, ..errors])
      }
    }
    Error(e) -> next(ctx, [e, ..errors])
  }
}

pub fn validate_linked_channel(
  ctx: BotContext,
  errors: List(error.BotError),
  next: fn(BotContext, List(error.BotError)) ->
    #(BotContext, List(error.BotError)),
) -> #(BotContext, List(error.BotError)) {
  let now = helpers.now()
  let cache_expired =
    ctx.session.chat_settings.linked_channel_id.updated_at
    + linked_channel_cache_ttl_sec
    < now

  use <- bool.lazy_guard(!cache_expired, fn() { next(ctx, errors) })

  case api_calls.get_chat(ctx, ctx.update.chat_id) {
    Ok(chat) -> {
      let linked_channel_id =
        cached.Cached(
          updated_at: now,
          value: chat.linked_chat_id |> option.unwrap(0),
        )

      case
        cs_storage.save_chat_property(
          ctx.session.db,
          ctx.update.chat_id,
          ["linked_channel_id"],
          cached.cacheify(linked_channel_id, fn(data) { json.int(data) }),
        )
      {
        Ok(_) -> {
          let chat_settings =
            ChatSettings(..ctx.session.chat_settings, linked_channel_id:)
          next(modify_ctx(ctx, chat_settings), errors)
        }
        Error(e) -> next(ctx, [e, ..errors])
      }
    }
    Error(e) -> next(ctx, [e, ..errors])
  }
}

fn modify_ctx(ctx: BotContext, chat_settings: ChatSettings) {
  let session = BotSession(..ctx.session, chat_settings:)
  bot.Context(..ctx, session:)
}
