import gleam/result
import infra/alias.{type BotContext}
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let msg =
    "Available settings:\n"
    <> "/strictModeNonMembers - strict mode for forwarded messages from linked channel + no reactions on all messages in chat. Applied only for non-members (comments from linked channel). Input 0 as argument to disable\n"
    <> "/banLang - check for messages with Chinese/Arabic/etc symbols. Applied only for non-members, channels and newcomers (if strictModeNewcomers enabled). For a complete list of languages look at unicode_script_extensions.txt in source code under the res folder\n"
    <> "/strictModeNewcomers <5> - strict mode for first <5> messages. Applied even if user was previously in the chat. Does not work for sender channels. Input 0 as argument to disable.\n"
    <> "/kickNewAccounts <8000000000> - kick all users with telegram id over given. \n"
    <> "/checkChatClones - bot will try to find accounts/channels whose name is similar to chat or linked channel title.\n"
    <> "/checkFemaleName - bot will kick joining accounts with ENG/RU female name.\n"
    <> "/trustuser <@username_or_id> - whitelist user. Reply with this command to trusted user OR specify username/userid.\n"
    <> "/useCas - bot will use Combot's anti-spam lists. Applied for joining users and non-members."
    <> "/banChannels - ban users who write on behalf of a channel. Applied for newcomers and non-members.\n"
    <> "\n"
    <> "/checkBannedWords - toggle ban for messages with banned words\n"
    <> "/banWord <word> - add or remove (if already exists) word to/from ban list, splitted by space. Also checks sender's name or chat title\n"
    <> "\n"
    <> "/listSettings - show current settings\n"
    <> "/help - show this message\n"

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
