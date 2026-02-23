import gleam/option
import infra/alias.{type BotContext}
import models/bot_session.{BotSession}
import telega/bot
import telega/update

pub fn extract_message_id() {
  fn(next) {
    fn(ctx: BotContext, update: update.Update) {
      let message_id = case update {
        update.AudioUpdate(message:, ..)
        | update.BusinessMessageUpdate(message:, ..)
        | update.CommandUpdate(message:, ..)
        | update.EditedBusinessMessageUpdate(message:, ..)
        | update.EditedMessageUpdate(message:, ..)
        | update.MessageUpdate(message:, ..)
        | update.PhotoUpdate(message:, ..)
        | update.TextUpdate(message:, ..)
        | update.VideoUpdate(message:, ..)
        | update.VoiceUpdate(message:, ..)
        | update.WebAppUpdate(message:, ..) -> option.Some(message.message_id)
        update.ChannelPostUpdate(post:, ..) -> option.Some(post.message_id)
        update.MessageReactionUpdate(message_reaction_updated:, ..) ->
          option.Some(message_reaction_updated.message_id)
        _ -> option.None
      }

      let session = BotSession(..ctx.session, message_id:)
      let modified_ctx = bot.Context(..ctx, session:)
      next(modified_ctx, update)
    }
  }
}
