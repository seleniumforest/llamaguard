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
  let banned_words = join_list_or(s.banned_words, "No banned words configured")
  let banned_lang =
    join_list_or(s.banned_languages, "No banned languages configured")
  let trusted_users =
    s.trusted_users
    |> list.map(fn(x) {
      //remove @ in list, so user won't be tagged unnecessary 
      case string.split_once(x, "@") {
        Ok(#(_, uname)) if uname != "" -> uname
        _ -> x
      }
    })
    |> join_list_or("No trusted users configured")

  let msg =
    log.format(
      "Current settings:\n
/kickNewAccounts: {0}
/strictModeNonMembers: {1}
/strictModeNewcomers: {2}
/checkChatClones : {3}
/checkFemaleName : {4}
/checkBannedWords: {5}
/useCas: {6}
/banChannels: {7}
Banned words: {8}
Trusted users (without @): {9}
Banned languages: {10}
",
      [
        s.kick_new_accounts |> string.inspect,
        s.strict_mode_nonmembers |> string.inspect,
        s.strict_mode_newcomers |> string.inspect,
        s.check_chat_clones |> string.inspect,
        s.check_female_name |> string.inspect,
        s.check_banned_words |> string.inspect,
        s.cas_enabled |> string.inspect,
        s.ban_channels |> string.inspect,
        banned_words,
        trusted_users,
        banned_lang,
      ],
    )

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}

fn join_list_or(ls: List(String), empty_msg: String) {
  case ls |> list.is_empty {
    False -> ls |> string.join(", ")
    True -> empty_msg
  }
}
