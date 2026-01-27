import infra/storage
import models/bot_session.{type BotSession}
import models/error.{type BotError}
import telega/bot.{type Context}

pub type BotContext =
  Context(BotSession(storage.StorageMessage), BotError)
