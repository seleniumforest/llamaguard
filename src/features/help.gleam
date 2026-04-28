import gleam/result
import infra/alias.{type BotContext}
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let msg =
    "Available commands:\n"
    <> "/kickNewAccounts <8000000000> - kick all users with telegram id over given\n"
    <> "/strictModeNonMembers - strict mode (no media, links, kickNewAccounts id limit, no channels, empty username) for forwarded messages from linked channel + no reactions on all messages in chat. Applied only for non-members. Input 0 as argument to disable\n"
    <> "/banLang - check for messages with Chinese/Arabic/etc symbols. Applied only for non-members (messages from linked channel), channels and newcomers (if strictModeNewcomers enabled). For a complete list of languages look at unicode_script_extensions.txt in source code under the res folder\n"
    <> "/strictModeNewcomers <5> - strict mode for first <5> messages. Does not work for sender channels. Input 0 as argument to disable.\n"
    <> "/checkChatClones - bot will try to find accounts/channels whose name is similar to chat title\n"
    <> "/checkFemaleName - bot will kick joining accounts with ENG/RU female name\n"
    <> "/trustuser <@username_or_id> - whitelist user. Reply with this command to trusted user OR specify username/userid\n"
    <> "/useCas - bot will use Combot's anti-spam lists for joining users and linked channel's comments"
    <> "/banChannels - ban users who write on behalf of a channel\n"
    <> "\n"
    <> "/checkBannedWords - toggle ban for messages with banned words\n"
    <> "/banWord <word> - add or remove (if already exists) word to/from ban list, splitted by space. Also checks sender's name or chat title\n"
    <> "\n"
    <> "/listSettings - show current settings\n"
    <> "/help - show this message\n"

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
