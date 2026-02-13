import gleam/list
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/log
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let s = ctx.session.chat_settings
  let words = case s.banned_words |> list.is_empty {
    False -> s.banned_words |> string.join(", ")
    True -> "No banned words configured"
  }

  let trusted_users = case s.trusted_users |> list.is_empty {
    False -> s.trusted_users |> string.join(", ")
    True -> "No trusted users configured"
  }

  let msg =
    log.format(
      "Current settings:\n
/kickNewAccounts: {0}
/strictModeNonMembers: {1}
/checkChatClones : {2}
/checkFemaleName : {3}
/checkBannedWords: {4}
Banned words: {5}
Trusted users: {6}
",
      [
        s.kick_new_accounts |> string.inspect,
        s.strict_mode_nonmembers |> string.inspect,
        s.check_chat_clones |> string.inspect,
        s.check_female_name |> string.inspect,
        s.check_banned_words |> string.inspect,
        words,
        trusted_users,
      ],
    )

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
