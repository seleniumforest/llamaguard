import infra/storage/kvstorage
import models/bot_session.{type BotSession}
import models/deps
import models/error.{type BotError}
import telega/bot.{type Context}

pub type BotContext =
  Context(BotSession, BotError, deps.Deps(kvstorage.StorageMessage))
