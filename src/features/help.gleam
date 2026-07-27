import gleam/result
import infra/alias.{type BotContext}
import infra/reply.{reply}
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  let msg =
    "Choose what user groups you want to filter:\n"
    <> "/strictModeNonMembers - strict mode* for comments from linked channel and reactions from non-members.\n"
    <> "/strictModeNewcomers <5> - strict mode for first <5> messages. Applied even if user was previously in the chat. Does not work for senders on behalf of a chat. Input 0 to disable.\n"
    <> "/strictModeChannels - strict mode for those who write on behalf of a channel.\n"
    <> "\n"
    <> "Available filters for strict mode:\n"
    <> "/banLang - check for messages for Han(Chinese)/Arabic/Hangul(Korean) etc symbols. For a complete list of languages look at unicode_script_extensions.txt in source code under the res folder (look bot's tg profile). [nm, nc, cs]**\n"
    <> "/kickNewAccounts <8000000000> - kick all users with telegram id over given. Input 0 to disable. [nm, nc].\n"
    <> "/checkChatClones - bot will try to find accounts/channels whose name is similar to chat or linked channel title. [nm, nc, cs].\n"
    <> "/checkFemaleName - bot will ban accounts with ENG/RU female name when they join or react. [nm, nc, cs].\n"
    <> "/useCas - bot will use Combot's anti-spam lists. [nm, nc].\n"
    <> "/banPhrase <phrase> - add or remove phrase to/from ban list. Case insensetive. Also checks sender's name/title and captions. [nm, nc, cs].\n"
    <> "\n"
    <> "Other filters:"
    <> "\n"
    <> "/banChannels - instantly bans everyone who write or put reaction on behalf of a channel.\n"
    <> "/trustuser <username_with_@_or_id> - whitelist user or channel. Reply with this command to trusted user OR specify username/userid.\n"
    //<> "/aggressive - checks for frequently used spam words, money amounts, em dashes and other unnatural symbols.\n"
    <> "\n"
    <> "/listSettings - show current settings\n"
    <> "/help - show this message\n"
    <> "\n"
    <> "*strict mode is to allow only plain text messages without stickers, links, media, bots, reactions etc.\n"
    <> "**[nm, nc, cs] = [Non-Members (users from comments + anon reactions), NewComers, ChatSenders]"

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
