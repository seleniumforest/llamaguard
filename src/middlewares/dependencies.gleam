import infra/alias.{type BotContext}
import infra/api_calls
import models/bot_session.{Deps}
import telega/bot.{Context}
import telega/update.{type Update}

pub fn inject_dependencies() {
  fn(next) {
    fn(ctx: BotContext, update: Update) {
      let session =
        bot_session.BotSession(
          ..ctx.session,
          dependencies: Deps(cas_check: api_calls.check_cas),
        )
      let modified_ctx = Context(..ctx, session:)
      next(modified_ctx, update)
    }
  }
}
