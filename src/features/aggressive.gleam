import infra/alias.{type BotContext}
import infra/cmd_utils
import models/error.{type BotError}
import telega/update.{type Command}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.flip_bool_setting_and_reply(
    ctx,
    ["aggressive"],
    fn(cs) { cs.aggressive },
    "Success: bot will use aggressive moderation.",
    "Success: bot won't use aggressive moderation anymore.",
  )
}
