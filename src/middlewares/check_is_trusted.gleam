import gleam/int
import gleam/list
import gleam/option
import infra/alias.{type BotContext}
import infra/helpers.{match_ids}
import telega/update

pub fn check_is_trusted() {
  fn(next) {
    fn(ctx: BotContext, upd: update.Update) {
      case upd {
        update.MessageUpdate(from_id:, message:, ..)
        | update.AudioUpdate(from_id:, message:, ..)
        | update.TextUpdate(from_id:, message:, ..)
        | update.VideoUpdate(from_id:, message:, ..)
        | update.VoiceUpdate(from_id:, message:, ..)
        | update.PhotoUpdate(from_id:, message:, ..)
        | update.EditedMessageUpdate(from_id:, message:, ..) -> {
          let id_to_match = from_id |> int.to_string
          let username_to_match =
            message.from
            |> option.map(fn(x) { x.username })
            |> option.flatten
            |> option.unwrap("")

          let is_trusted =
            ctx.session.chat_settings.trusted_users
            |> list.any(fn(x) {
              match_ids(x, id_to_match) || match_ids(x, username_to_match)
            })

          case is_trusted {
            False -> next(ctx, upd)
            True -> Ok(ctx)
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
