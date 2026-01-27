import dot_env as dot
import dot_env/env
import features/banned_words
import features/check_chat_clones
import features/check_female_name
import features/help
import features/kick_new_accounts
import features/list_settings
import features/strict_mode_nonmembers
import gleam/erlang/process
import gleam/option
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import infra/storage
import middlewares/check_is_admin.{check_is_admin}
import middlewares/extract_message_id.{extract_message_id}
import middlewares/inject_chat_settings.{inject_chat_settings}
import middlewares/resources.{inject_resources}
import models/bot_session
import models/error.{type BotError}
import telega
import telega/bot.{SessionSettings}
import telega/polling
import telega/router
import telega/update.{type Update}

pub fn main() {
  dot.new() |> dot.load
  let db = storage.init()
  let resources = resources.load_static_resources()

  let router =
    router.new("default")
    |> router.use_middleware(check_is_admin())
    |> router.use_middleware(inject_chat_settings(db))
    |> router.use_middleware(inject_resources(resources))
    |> router.use_middleware(extract_message_id())
    |> router.on_custom(fn(_) { True }, handle_update)
    |> router.on_command("kickNewAccounts", kick_new_accounts.command)
    |> router.on_command("checkChatClones", check_chat_clones.command)
    |> router.on_command("checkFemaleName", check_female_name.command)
    |> router.on_command("strictModeNonMembers", strict_mode_nonmembers.command)
    |> router.on_command("checkBannedWords", banned_words.command)
    |> router.on_command("addBanWord", banned_words.add_word_command)
    |> router.on_command("removeBanWord", banned_words.remove_word_command)
    |> router.on_command("listSettings", list_settings.command)
    |> router.on_commands(["help", "start"], help.command)

  let assert Ok(token) = env.get_string("BOT_TOKEN")
  let assert Ok(bot) =
    telega.new_for_polling(token:)
    |> telega.with_router(router)
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
    |> telega.init_for_polling()

  let assert Ok(poller) =
    polling.start_polling_with_offset(
      bot,
      -1,
      timeout: 20,
      limit: 100,
      allowed_updates: [
        "message",
        "edited_message",
        "channel_post",
        "edited_channel_post",
        //"message_reaction",
        "inline_query",
        "chosen_inline_result",
        "chat_member",
      ],
      poll_interval: 1000,
    )

  polling.wait_finish(poller)
}

fn handle_update(ctx: BotContext, upd: Update) -> Result(BotContext, BotError) {
  process.spawn_unlinked(fn() {
    use ctx, upd <- kick_new_accounts.checker(ctx, upd)
    use ctx, upd <- strict_mode_nonmembers.checker(ctx, upd)
    use ctx, upd <- check_chat_clones.checker(ctx, upd)
    use ctx, upd <- check_female_name.checker(ctx, upd)
    use _ctx, _upd <- banned_words.checker(ctx, upd)
    Nil
  })
  Ok(ctx)
}
