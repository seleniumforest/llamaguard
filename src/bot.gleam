import dot_env as dot
import dot_env/env
import features/ban_channels
import features/ban_language
import features/banned_words
import features/cas
import features/check_chat_clones
import features/check_female_name
import features/help
import features/kick_new_accounts
import features/list_settings
import features/strict_mode_newcomers
import features/strict_mode_nonmembers
import features/trust_user
import gleam/erlang/process
import gleam/option
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import infra/storage/kvstorage
import middlewares/dependencies.{inject_dependencies}
import middlewares/inject_context.{inject_chat_settings, inject_user_chat}
import middlewares/newcomers_events.{newcomers_events}
import middlewares/resources.{inject_resources}
import middlewares/setup_permissions.{setup_permissions}
import models/bot_session
import models/error.{type BotError}
import telega
import telega/bot.{SessionSettings}
import telega/router
import telega/update.{type Update}
import telega_httpc

pub fn main() {
  dot.new() |> dot.load
  let db = kvstorage.init("file:data.sqlite3")
  let resources = resources.load_static_resources()

  let router =
    router.new("default")
    |> router.use_middleware(inject_dependencies())
    |> router.use_middleware(inject_chat_settings(db))
    |> router.use_middleware(inject_user_chat())
    |> router.use_middleware(inject_resources(resources))
    |> router.use_middleware(setup_permissions())
    |> router.use_middleware(newcomers_events())
    |> router.on_custom(fn(_) { True }, handle_update)
    |> router.on_command("kickNewAccounts", kick_new_accounts.command)
    |> router.on_command("checkChatClones", check_chat_clones.command)
    |> router.on_command("checkFemaleName", check_female_name.command)
    |> router.on_command("strictModeNonMembers", strict_mode_nonmembers.command)
    |> router.on_command("strictModeNewcomers", strict_mode_newcomers.command)
    |> router.on_command("trustuser", trust_user.command)
    |> router.on_command("checkBannedWords", banned_words.command)
    |> router.on_command("useCas", cas.command)
    |> router.on_command("banChannels", ban_channels.command)
    |> router.on_command("banWord", banned_words.add_or_remove_words)
    |> router.on_command("banLang", ban_language.command)
    |> router.on_command("listSettings", list_settings.command)
    |> router.on_commands(["help", "start"], help.command)

  let assert Ok(token) = env.get_string("BOT_TOKEN")
  let client = telega_httpc.new(token:)
  let assert Ok(_) =
    telega.new_for_polling(client)
    |> telega.with_router(router)
    //|> telega.set_drop_pending_updates(True)
    |> telega.with_catch_handler(fn(_ctx, err) {
      log.print_err(err |> string.inspect)
      Ok(Nil)
    })
    |> telega.with_session_settings(
      SessionSettings(
        persist_session: fn(_key, session) { Ok(session) },
        get_session: fn(_key) { bot_session.default(db) |> option.Some |> Ok },
        default_session: fn() { bot_session.default(db) },
      ),
    )
    |> telega.with_polling_config(20, 100, 1000)
    |> telega.set_allowed_updates([
      "message",
      "edited_message",
      "channel_post",
      "edited_channel_post",
      "message_reaction",
      "inline_query",
      "chosen_inline_result",
      "chat_member",
      "callback_query",
    ])
    |> telega.init_for_polling()

  process.sleep_forever()
}

fn handle_update(ctx: BotContext, upd: Update) -> Result(BotContext, BotError) {
  //echo upd
  process.spawn_unlinked(fn() {
    //skip handling from admins, linked channel and trusted list. Always comes first
    //use ctx, upd <- trust_user.checker(ctx, upd)
    //checker to count newcomers' messages
    use ctx, upd <- strict_mode_newcomers.checker(ctx, upd)
    use ctx, upd <- ban_channels.checker(ctx, upd)
    use ctx, upd <- kick_new_accounts.checker(ctx, upd)
    use ctx, upd <- check_chat_clones.checker(ctx, upd)
    use ctx, upd <- check_female_name.checker(ctx, upd)
    use ctx, upd <- ban_language.checker(ctx, upd)
    use ctx, upd <- banned_words.checker(ctx, upd)
    use ctx, upd <- cas.checker(ctx, upd)
    use _ctx, _upd <- strict_mode_nonmembers.checker(ctx, upd)
    Nil
  })
  Ok(ctx)
}
