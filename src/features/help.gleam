import gleam/result
import infra/alias.{type BotContext}
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let msg =
    "Available commands:\n"
    <> "/kickNewAccounts <8000000000> - kick all users with telegram id over given.\n"
    <> "/strictModeNonMembers - strict mode (no media, links, reactions, kickNewAccounts id limit, no channels, empty username) for forwarded messages from linked channel\n"
    <> "/checkChatClones - bot will try to find accounts/channels whose name is similar to chat title\n"
    <> "/checkFemaleName - bot will kick joining accounts with ENG/RU female name\n"
    <> "/trust <@username> - whitelist user. Reply with this message to trusted user OR specify username\n"
    <> "\n"
    <> "/checkBannedWords - toggle ban for messages with banned words\n"
    <> "/addBanWord <word> - add word to ban list\n"
    <> "/removeBanWord <word> - remove word from ban list\n"
    <> "\n"
    <> "/listSettings - show all settings\n"
    <> "/help - show this message"

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
