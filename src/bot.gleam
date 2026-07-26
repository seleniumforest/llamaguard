import dot_env as dot
import dot_env/env
import features/aggressive
import features/ban_channels
import features/ban_language
import features/banned_words
import features/cas
import features/check_chat_clones
import features/check_female_name
import features/help
import features/kick_new_accounts
import features/list_settings
import features/strict_mode_channels
import features/strict_mode_newcomers
import features/strict_mode_nonmembers
import features/trust_user
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import infra/alias.{type BotContext}
import infra/handle
import infra/log
import infra/storage/kvstorage
import middlewares/dependencies.{inject_dependencies}
import middlewares/inject_context.{inject_chat_settings, inject_user_chat}
import middlewares/new_admins.{revalidate_new_admins}
import middlewares/newcomers_events.{newcomers_events}
import middlewares/resources.{inject_resources}
import middlewares/setup_flags.{setup_flags}
import models/bot_session
import models/deps
import models/error.{type BotError}
import telega
import telega/bot.{SessionSettings}
import telega/router
import telega/storage/ets
import telega/update.{type Update}
import telega_httpc

pub fn main() {
  dot.new() |> dot.load
  let db = kvstorage.init("file:data.sqlite3")
  let resources = resources.load_static_resources()
  let assert Ok(cache) = ets.new("cache")

  let router =
    router.new("default")
    |> router.use_middleware(inject_dependencies())
    |> router.use_middleware(inject_chat_settings(db))
    |> router.use_middleware(inject_user_chat())
    |> router.use_middleware(inject_resources(resources))
    |> router.use_middleware(revalidate_new_admins())
    |> router.use_middleware(setup_flags())
    |> router.use_middleware(newcomers_events())
    |> router.on_command("kickNewAccounts", kick_new_accounts.command)
    |> router.on_command("checkChatClones", check_chat_clones.command)
    |> router.on_command("checkFemaleName", check_female_name.command)
    |> router.on_command("strictModeNonMembers", strict_mode_nonmembers.command)
    |> router.on_command("strictModeNewcomers", strict_mode_newcomers.command)
    |> router.on_command("strictModeChannels", strict_mode_channels.command)
    |> router.on_commands(["trustuser", "trustUser"], trust_user.command)
    |> router.on_command("checkBannedWords", banned_words.command)
    |> router.on_command("useCas", cas.command)
    |> router.on_command("banChannels", ban_channels.command)
    |> router.on_command("banPhrase", banned_words.command)
    |> router.on_command("banLang", ban_language.command)
    |> router.on_command("aggressive", aggressive.command)
    |> router.on_commands(
      ["listSettings", "listsettings"],
      list_settings.command,
    )
    |> router.on_commands(["help", "start"], help.command)
    |> router.on_custom(should_check, handle_update)

  let assert Ok(token) = env.get_string("BOT_TOKEN")
  let assert Ok(_) =
    telega.new_for_polling(telega_httpc.new(token:))
    |> telega.with_dependencies(deps.Deps(cache:))
    |> telega.with_router(router)
    |> telega.set_drop_pending_updates(True)
    |> telega.with_catch_handler(fn(ctx, err) {
      log.print_err(ctx.session |> string.inspect)
      log.print_err(err |> string.inspect)
      Ok(Nil)
    })
    |> telega.with_session_settings(
      SessionSettings(
        persist_session: fn(_key, session) { Ok(session) },
        get_session: fn(_key) { bot_session.default(db) |> Some |> Ok },
        default_session: fn() { bot_session.default(db) },
      ),
    )
    //for some reason, fails on my server with default settings
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
  //to avoid "race conditions" make spawns per-sender
  process.spawn_unlinked(fn() {
    use ctx, upd <- strict_mode_newcomers.checker(ctx, upd)
    use ctx, upd <- strict_mode_channels.checker(ctx, upd)
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

pub fn should_check(upd: Update) -> Bool {
  use message <- handle.msg(upd, fn() { True })

  let is_user_join_or_leave_system_msg = case
    message.left_chat_member,
    message.new_chat_members
  {
    Some(_), None -> True
    None, Some(users) -> users |> list.length > 0
    _, _ -> False
  }

  //https://core.telegram.org/bots/api#message
  //idk should i check all service msgs for now
  case is_user_join_or_leave_system_msg {
    True -> False
    False -> True
  }
}
